import ../screenutils/screenrenderer
import ../data/[spaceentity, insensitivestrings, worlds]

type
  TextInput* = object
    str*: string
    pos*: int
    suggestionInd*: int = -1
    suggestion*: string

  FocusDirection* = enum Up, Right, Down, Left

  ScreenKind* = enum
    NoSplit
    SplitH
    SplitV

  ScreenAction* = enum
    Nothing
    Close
    SplitH
    SplitV

  Screen* = ref object
    x*, y*, w*, h*: float32
    parent* {.cursor.} : Screen
    splitPercentage*: float32 = 1f
    case kind*: ScreenKind
    of NoSplit:
      buffer*: Buffer
      activeProgram*: InsensitiveString
      input*: TextInput
      programX*: int
      programY*: int
      shipStack*: seq[ControlledEntity] ## Stack for which ship is presently controlled
        ## [^1] is active
        ## [0] is the player's
      action*: ScreenAction
    of SplitH, SplitV:
      left*: Screen
      right*: Screen


  ScreenObj* = typeof(Screen()[])


iterator screens*(screen: Screen): Screen =
  var queue = @[screen]
  while queue.len > 0:
    let screen = queue.pop()
    case screen.kind
    of NoSplit:
      if screen.w != 0 and screen.h != 0:
        yield screen
    else:
      queue.add [screen.left, screen.right]

proc recalculate*(screen: Screen) =
  var screens = @[screen]
  while screens.len > 0:
    let screen = screens.pop()
    case screen.kind
    of SplitV, SplitH:
      let
        splitVMod = float(screen.kind == SplitV)
        splitHMod = 1f - splitVMod

      screen.left.x = screen.x
      screen.right.x = screen.x + (screen.w * screen.splitPercentage) * splitVMod

      screen.left.y = screen.y
      screen.right.y = screen.y + (screen.h * screen.splitPercentage) * splitHMod


      screen.left.h = screen.h - (screen.h * splitHMod * (1 - screen.splitPercentage))
      screen.right.h = screen.h - (screen.h * splitHMod * screen.splitPercentage)

      screen.left.w = screen.w - (screen.w * splitVMod * (1 - screen.splitPercentage))
      screen.right.w = screen.w - (screen.w * splitVMod * screen.splitPercentage)


      screens.add screen.left
      screens.add screen.right
    of NoSplit:
      if screen.w != 0 and screen.h != 0:
        screen.buffer.setLineWidth(int screen.w)
        screen.buffer.setLineHeight(int screen.h)

proc focus*(root, currentScreen: Screen, dir: FocusDirection): Screen =
  var
    distX = float32.high
    distY = float32.high

  result = currentScreen

  const conds = [
      Up: (proc(screen, currentScreen: Screen): bool = screen.y < currentScreen.y),
      Right: (proc(screen, currentScreen: Screen): bool = screen.x > currentScreen.x),
      Down: (proc(screen, currentScreen: Screen): bool = screen.y > currentScreen.y),
      Left: (proc(screen, currentScreen: Screen): bool = screen.x < currentScreen.x),
  ]

  for screen in root.screens:
    if screen != currentScreen:
      let
        scrDistX = abs(screen.x - currentScreen.x)
        scrDistY = abs(screen.y - currentScreen.y)
      if conds[dir](screen, currentScreen) and scrDistX <= distX and scrDistY <= distY:
        result = screen
        distX = scrDistx
        distY = scrDistY
