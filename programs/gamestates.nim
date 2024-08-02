import ../screenutils/screenrenderer
import ../data/[spaceentity, insensitivestrings]
import pkg/[traitor, chroma, pixie]
import std/[tables, strutils, hashes, random]
import pkg/truss3D/[inputs]

export screenrenderer, chroma, pixie

type
  ProgramFlag* = enum
    Blocking ## For things like manpage, no need to clear just do not print `> ...` next

  ProgramFlags* = set[ProgramFlag]

  Program* = distinct tuple[
    onExit: proc(_: var Atom, gameState: var GameState) {.nimcall.},
    update: proc(_: var Atom, gameState: var GameState, dt: float32, active: bool) {.nimcall.},
    name: proc(_: Atom): string {.nimcall.},
    getFlags: proc(_: Atom): set[ProgramFlag] {.nimcall.}
  ]
  CommandHandler* = proc(gamestate: var Gamestate, input: string)

  Command* = object
    name*: string
    help*: string
    manual*: string # Manpage
    handler*: CommandHandler
    suggest*: proc(gs: GameState, input: string, ind: var int): string ## Suggests a field that can be entered to fill out

  InputShow = enum
    WithCursor
    WithSuggestion

  TextInput* = object
    str*: string
    pos*: int
    suggestionInd*: int = -1
    suggestion*: string

  ScreenKind = enum
    NoSplit
    SplitH
    SplitV

  ScreenAction = enum
    Nothing
    Close
    SplitH
    SplitV

  Screen = ref object
    x*, y*, w*, h*: float32
    parent: Screen
    case kind: ScreenKind
    of NoSplit:
      buffer*: Buffer
      activeProgram: InsensitiveString
      input: TextInput
      programX: int
      programY: int
      shipStack: seq[string] ## Stack of names for which ship is presently controlled
        ## [^1] is active
        ## [0] is the player's
      action: ScreenAction
    of SplitH, SplitV:
      left*: Screen
      right*: Screen

  ScreenObj = typeof(Screen()[])

  GameState* = object
    rootScreen: Screen
    screen*: Screen
    screenCount: int

    programs: Table[string, Table[InsensitiveString, Traitor[Program]]]
    handlers: Table[InsensitiveString, Command]

    history: seq[string]
    historyPos: int

    programX: int
    programY: int
    world*: World


    screenWidth*: int # character size of current screen
    screenHeight*: int

    fpsX, fpsY: int # Where we write to
    lastFpsBuffer: seq[Glyph]

    curveAmount*: float32 # The curve amount

implTrait Program

iterator commands*(gameState: GameState): Command =
  for command in gamestate.handlers.values:
    yield command

iterator screens*(gameState: var GameState): Screen =
  var queue = @[gameState.rootScreen]
  while queue.len > 0:
    let screen = queue.pop()
    case screen.kind
    of NoSplit:
      if screen.w != 0 and screen.h != 0:
        yield screen
    else:
      queue.add [screen.left, screen.right]

proc input(gameState: GameState): lent TextInput = gameState.screen.input
proc input(gameState: var GameState): var TextInput = gameState.screen.input

proc buffer*(gameState: var GameState): var Buffer =
  gameState.screen.buffer

proc writeError*(gameState: var GameState, msg: string) =
  gameState.buffer.put(msg, GlyphProperties(foreground: parseHtmlColor"red"))

proc activeShip*(gameState: GameState): lent string =
  gameState.screen.shipStack[gameState.screen.shipStack.high]

proc activeShipEntity*(gameState: GameState): lent SpaceEntity =
  gameState.world.getEntity(gameState.activeShip)

proc activeShipEntity*(gameState: var GameState): var SpaceEntity =
  gameState.world.getEntity(gameState.activeShip)

proc enterProgram*(gameState: var GameState, program: Traitor[Program]) =
  (gameState.screen.programX, gameState.screen.programY) = gamestate.buffer.getPosition()
  gameState.buffer.clearTo(gameState.screen.programY)

  var programName = InsensitiveString program.name()
  discard gamestate.programs.hasKeyOrPut(gameState.activeShip, initTable[InsensitiveString, Traitor[Program]]())
  gamestate.programs[gameState.activeShip][programName] = program
  gameState.screen.activeProgram = programName

proc enterProgram*(gameState: var GameState, program: sink string) =
  gameState.screen.activeProgram = InsensitiveString program


proc activeProgramTrait(gameState: GameState, screen: Screen): Traitor[Program] =
  if gameState.activeShip in gameState.programs and screen.activeProgram in gameState.programs[gameState.activeShip]:
    gameState.programs[gameState.activeShip][screen.activeProgram]
  else:
    nil

proc exitProgram*(gameState: var GameState) =
  gameState.activeProgramTrait(gamestate.screen).onExit(gameState)
  gameState.screen.activeProgram = insStr""
  gamestate.buffer.showCursor(0)
  gameState.input.pos = 0
  gameState.input.str.setLen(0)

proc hasProgram*(gameState: var GameState, name: string): bool =
  gameState.activeShip in gameState.programs and name.InsensitiveString in gameState.programs[gameState.activeShip]

proc hasCommand*(gameState: var GameState, name: string): bool = InsensitiveString(name) in gameState.handlers
proc getCommand*(gameState: var GameState, name: string): lent Command = gameState.handlers[InsensitiveString(name)]

proc entityExists*(gameState: var GameState, name: string): bool =
  gameState.world.entityExists(name)

proc getEntity*(gameState: GameState, name: string): lent SpaceEntity =
  gameState.world.getEntity(name)

proc getEntity*(gameState: var GameState, name: string): var SpaceEntity =
  gameState.world.getEntity(name)

proc takeControlOf*(gameState: var GameState, name: string): bool =
  ## takes control of a ship returning true if it can be found and connected to
  result = gameState.world.entityExists(name) and name != gameState.screen.shipStack[^1] # O(N) Send help!
  if result:
    gameState.screen.shipStack.add name
    gameState.buffer.properties = gameState.activeShipEntity.shipData.glyphProperties

proc randState*(gameState: var GameState): var Rand = gameState.world.randState

proc popInput*(gameState: var GameState): string =
  result = move(gameState.input.str)
  gameState.input.pos = 0
  gameState.input.str.setLen(0)
  gameState.input.suggestion = ""
  gameState.input.suggestionInd = -1

proc peekInput*(gameState: GameState): TextInput = gameState.input

proc showInput*(gameState: var GameState, renderFlags = {WithCursor}) =
  if WithCursor in renderFlags:
    gameState.buffer.showCursor(gameState.input.pos)
  gameState.buffer.put(gameState.input.str)
  if WithSuggestion in renderFlags:
    var prop = gameState.buffer.properties
    prop.foreground.r *= 0.75
    prop.foreground.g *= 0.75
    prop.foreground.b *= 0.75
    gameState.buffer.put(gameState.input.suggestion, props = prop)

import programutils
export programutils

importAllCommands()

proc insert(s: var string, at: int, toInsert: string) =
  let origEnd = s.high
  s.setLen(s.len + toInsert.len)
  cast[ptr seq[char]](s.addr)[at + toInsert.len..^1] = s.toOpenArray(at, origEnd)
  s[at..at + toInsert.high] = toInsert

proc add*(gameState: var GameState, command: Command) =
  gameState.handlers[InsensitiveString(command.name)] = command

proc splitVertical(gameState: var GameState, screen: Screen) =
  screen.action = Nothing
  screen.buffer.setLineWidth screen.buffer.lineWidth div 2
  var buff = Buffer(
    lineWidth: screen.buffer.lineWidth,
    lineHeight: screen.buffer.lineHeight
  )
  buff.initFrom(gamestate.screen.buffer)
  #buff.initResources("PublicPixel.ttf", true, fontSize = 80)
  buff.put("")

  var oldScreen = move screen[]
  let origWidth = oldScreen.w
  oldScreen.w = oldScreen.w / 2
  let newScreen = Screen(
      kind: NoSplit,
      x: oldScreen.x + oldScreen.w,
      y: oldScreen.y,
      w: oldScreen.w,
      h: oldScreen.h,
      buffer: buff,
      shipStack: oldScreen.shipStack,
    )
  screen[] = ScreenObj(
    kind: SplitV,
    x: oldScreen.x,
    y: oldScreen.y,
    w: origWidth,
    h: oldScreen.h,
    left: Screen(),
    right: newScreen,
    parent: oldScreen.parent
  )
  screen.left[] = oldScreen
  screen.left.parent = screen
  screen.right.parent = screen
  gameState.screen = screen.left
  inc gameState.screenCount

proc splitHorizontal(gameState: var GameState, screen: Screen) =
  screen.action = Nothing
  screen.buffer.setLineHeight screen.buffer.lineHeight div 2
  var buff = Buffer(
    lineWidth: screen.buffer.lineWidth,
    lineHeight: screen.buffer.lineHeight,
    properties: GlyphProperties(foreground: parseHtmlColor("White"))
  )
  buff.initFrom(gamestate.screen.buffer)
  #buff.initResources("PublicPixel.ttf", true, fontSize = 80)
  buff.put("")
  var oldScreen = move screen[]
  let origHeight = oldScreen.h
  oldScreen.h = oldScreen.h / 2
  let newScreen = Screen(
      kind: NoSplit,
      x: oldScreen.x,
      y: oldScreen.y + oldScreen.h,
      w: oldScreen.w,
      h: oldScreen.h,
      buffer: buff,
      shipStack: oldScreen.shipStack,
    )
  screen[] = ScreenObj(
    kind: SplitH,
    x: oldScreen.x,
    y: oldScreen.y,
    w: oldScreen.w,
    h: origHeight,
    left: Screen(),
    right: newScreen,
    parent: oldScreen.parent
  )
  screen.left[] = oldScreen
  screen.left.parent = screen
  screen.right.parent = screen
  gameState.screen = screen.left
  inc gameState.screenCount

proc closeScreen(gameState: var Gamestate, screen: Screen) =
  screen.action = Nothing
  let
    theParent = screen.parent
    theSplit = move screen.parent[]

  assert theSplit.kind != NoSplit

  theParent[] =
    if screen == theSplit.left:
      move theSplit.right[]
    elif screen == theSplit.right:
      move theSplit.left[]
    else:
      raiseAssert "Unreachable screen has to be left or right of it's parent"

  theParent.x = theSplit.x
  theParent.y = theSplit.y
  theParent.w = theSplit.w
  theParent.h = theSplit.h

  gameState.screen = theParent

  theParent.parent = theSplit.parent

  if theParent.parent == nil:
    gameState.rootScreen = theParent
  else:
    assert theSplit.parent.kind != NoSplit

  theParent.buffer.setLineWidth int(theParent.w)
  theParent.buffer.setLineHeight int(theParent.h)
  dec gameState.screenCount


proc init*(_: typedesc[GameState]): GameState =
  #[
  result.add Command(
    name: "toggle3d",
    help: "This toggles 3D view on and off",
    handler: proc(gameState: var GameState, _: string) = gamestate.buffer.toggleFrameBuffer()
  )
  ]#

  result.add Command(
    name: "debug",
    help: "Prints lines for debugging the buffer",
    handler: proc(gameState: var GameState, _: string) =
      for i in 1..gameState.buffer.lineHeight:
        gameState.buffer.put $i & repeat("=", gameState.buffer.lineWidth)
        gameState.buffer.newLine()
  )

  result.add Command(
    name: "exit",
    help: "Exits the currently controlled ship.",
    handler: proc(gameState: var GameState, input: string) =
      if input == "player":
        gameState.screen.shipStack.setLen(1)
      elif gameState.screen.shipStack.len > 1:
        gameState.buffer.properties = gameState.getEntity(gameState.screen.shipStack[^2]).shipData.glyphProperties
        gameState.buffer.put("Exited: " & gameState.activeShip & "\n")
        gameState.screen.shipStack.setLen(gameState.screen.shipStack.high)
      else:
        gameState.buffer.put("Where do you want to go,")
        gameState.buffer.put(" SPACE?\n", GlyphProperties(
          foreground: gameState.buffer.properties.foreground,
          background: gameState.buffer.properties.background,
          shakeStrength: 5, shakeSpeed: 30)
        )
  )

  result.add Command(
    name: "clear",
    help: "Clears the screen",
    handler: proc(gameState: var GameState, _: string) = gamestate.buffer.toBottom()
  )

  result.add Command(
    name: "curve",
    help: "Adjust the curve amount",
    handler: proc(gameState: var GameState, amount: string) =
      let amnt =
        try:
          parseFloat(amount.strip())
        except CatchableError as e:
          gameState.writeError(e.msg)
          gameState.buffer.newLine()
          return
      if amnt notin 0f..1f:
        gameState.writeError("Expected value in `0..1` range.\n")
      else:
        gameState.curveAmount = amnt

  )


  result.add Command(
    name: "programs",
    help: "Lists all running programs for the current ship",
    handler: (
      proc(gameState: var GameState, input: string) =
        if input.isEmptyOrWhitespace():
          if gameState.activeShip in gameState.programs:
            for key in gameState.programs[gameState.activeShip].keys:
              gameState.buffer.put(key)
              gameState.buffer.newLine()
          else:
            gameState.buffer.put("No programs running on this ship.")
            gameState.buffer.newLine()
        else:
          gameState.screen.activeProgram = InsensitiveString input.strip()
          if gameState.activeShip notin gameState.programs or gameState.screen.activeProgram notin gameState.programs[gameState.activeShip]:
            gameState.writeError("No program found named '" & gameState.screen.activeProgram & "' for the present ship.")
            gameState.screen.activeProgram = InsensitiveString""
    ),
    suggest:(
      proc(gameState: GameState, input: string, ind: var int): string =
        iterator programsIter(gameState: GameState): string =
          if gameState.activeShip in gameState.programs:
            for key in gameState.programs[gameState.activeShip].keys:
              yield string key
        case input.suggestIndex()
        of 0, 1:
          suggestNext(gameState.programsIter, input, ind)
        else:
          ""
    ),
  )

  result.add Command(
    name: "splitv",
    help: "Splits the current terminal vertically. The left side maintains history",
    handler: proc(gameState: var GameState, _: string) =
      if gameState.buffer.lineWidth div 2 < 10:
        gameState.writeError("Cannot make the buffer, width would be too small\n")
        return
      gameState.screen.action = SplitV

  )
  result.add Command(
    name: "splith",
    help: "Splits the current terminal horizontally. The top side maintains history",
    handler: proc(gameState: var GameState, _: string) =
      if gameState.buffer.lineHeight div 2 < 10:
        gameState.writeError("Cannot make the buffer, height would be too small")
        return
      gameState.screen.action = SplitH
  )


  result.add Command(
    name: "close",
    help: "Closes the active window if it is not the last opened window.",
    handler: proc(gameState: var GameState, _: string) =
      assert gameState.screen.kind == NoSplit
      if gameState.screen != gameState.rootScreen:
        gameState.screen.action = Close
      else:
        gameState.buffer.put("To quit the game run 'quit really'.\n")

  )

  for command in programutils.commands():
    result.add command

  result.screenWidth = 100
  result.screenHeight = 60

  var buff = Buffer(lineWidth: result.screenWidth, lineHeight: result.screenHeight, properties: GlyphProperties(foreground: parseHtmlColor("White")))
  buff.initResources("PublicPixel.ttf", true, fontSize = 80)
  result.rootScreen = Screen(kind: NoSplit, buffer: buff, w: result.screenWidth.float32, h: result.screenHeight.float32)
  result.screen = result.rootScreen
  inc result.screenCount


proc clearSuggestion(gameState: var GameState) =
  gamestate.input.suggestion = ""
  gamestate.input.suggestionInd = -1

proc takeSuggestion(gameState: var GameState) =
  gameState.input.str.add gameState.input.suggestion
  gameState.input.str.add " "
  gameState.input.pos = gameState.input.str.len
  gameState.clearSuggestion()

proc dispatchCommand(gameState: var GameState) =
  let input = gameState.popInput()
  if not input.isEmptyOrWhitespace():
    gameState.history.add input
  gameState.historyPos = 0
  if input.len > 0:
    let
      ind =
        if (let ind = input.find(' '); ind) != -1:
          ind - 1
        else:
          input.high
      command = insStr input[0..ind]
    gameState.buffer.newLine()
    if command in gamestate.handlers:
      gameState.clearSuggestion()
      gamestate.handlers[command].handler(gameState, input[ind + 1 .. input.high])
    else:
      gameState.writeError("Incorrect command\n")


proc suggest(gameState: var GameState) =
  let input = gameState.input.str

  if input.find(WhiteSpace) != -1 and input.len > 0: # In the case we have a command we dispatch a command
    let
      ind =
        if (let ind = input.find(' '); ind) != -1:
          ind - 1
        else:
          input.high
      command = insStr input[0..ind]
    if command in gamestate.handlers and gamestate.handlers[command].suggest != nil:
      gameState.input.suggestion = gamestate.handlers[command].suggest(gameState, input[ind + 1 .. input.high], gameState.input.suggestionInd)
  else: # We search top level commands
    iterator handlerStrKeys(gameState: GameState): string =
      for key in gameState.handlers.keys:
        yield string key
    gameState.input.suggestion = suggestNext(gameState.handlerStrKeys, input, gameState.input.suggestionInd)


proc inProgram(screen: Screen): bool = screen.activeProgram != ""
proc currentProgramFlags(gameState: GameState, screen: Screen): ProgramFlags =
  if screen.inProgram:
    let prog = gameState.activeProgramTrait(screen)
    if prog == nil:
      {}
    else:
      prog.getFlags()
  else:
    {}

proc update*(gameState: var GameState, dt: float) =
  var dirtiedInput = false
  proc dirtyInput() = dirtiedInput = true

  if KeyCodeLAlt.isDownRepeating():
    if gameState.screen.kind == NoSplit and gameState.screen.parent != nil:
      if gameState.screen.parent.left == gameState.screen:
        gameState.screen = gameState.screen.parent.right
      else:
        gameState.screen = gameState.screen.parent.left
      dirtyInput()

  if inputText().len > 0:
    gameState.input.str.insert gameState.input.pos, inputText()
    gameState.input.pos.inc inputText().len
    setInputText("")
    gameState.clearSuggestion()
    dirtyInput()


  let startShipCount = gameState.screen.shipStack.len

  if startShipCount > 0:
    gameState.buffer.properties = gameState.activeShipEntity.shipData.glyphProperties

  if KeyCodeBackspace.isDownRepeating() and gameState.input.pos > 0 and gameState.input.str.len > 0:
    gameState.input.str.delete(gameState.input.pos - 1 .. gameState.input.pos - 1)
    dec gameState.input.pos
    gameState.clearSuggestion()
    dirtyInput()


  if KeycodeLeft.isDownRepeating:
    gameState.input.pos = max(gameState.input.pos - 1, 0)
    dirtyInput()


  if KeycodeRight.isDownRepeating:
    if gameState.input.suggestionInd != -1:
      gameState.takeSuggestion()
    else:
      gameState.input.pos = min(gameState.input.pos + 1, gameState.input.str.len)
    dirtyInput()



  if KeycodeTab.isDownRepeating():
    gameState.suggest()
    dirtyInput()

  if not gamestate.world.isReady:
    gamestate.buffer.setPosition(0, 0)
    gamestate.buffer.put "Shall we play a game?\n"
    gamestate.buffer.put "Enter your Ship name:\n"
    gameState.buffer.clearLine()
    gameState.showInput()

    if KeyCodeReturn.isDownRepeating() and gameState.input.str.len > 0:
      let name = gameState.popInput()
      gameState.screen.shipStack.add name
      gameState.world.init(name, name) # TODO: Take a seed aswell
      gameState.buffer.clearTo(0)
      gameState.buffer.put ">"
      gameState.showInput()

    gameState.screen.buffer.upload(dt)
  else:
    gamestate.world.update(dt)


    for programs in gamestate.programs.mvalues:
      for key, program in programs.mpairs:
        var found = false
        for screen in gameState.screens:
          if key == screen.activeProgram:
            found = true
            break
        if not found:
          program.update(gamestate, dt, false)


    for screen in gamestate.screens:
      let
        isActiveScreen = gameState.screen == screen
        oldScreen = gameState.screen
      gameState.screen = screen
      if not screen.inProgram or Blocking in gameState.currentProgramFlags(gameState.screen):
        if KeyCodePageUp.isDownRepeating() and isActiveScreen: # Scrollup
          gameState.buffer.scrollUp()

        if KeyCodePageDown.isDownRepeating() and isActiveScreen: # Scroll Down
          gameState.buffer.scrollDown()

        if Blocking notin gameState.currentProgramFlags(gameState.screen):
          if KeyCodeReturn.isDownRepeating() and isActiveScreen: # Enter
            if gameState.input.suggestion.len > 0:
              gameState.takeSuggestion()
            else:
              gameState.dispatchCommand()
            dirtyInput()

          if KeyCodeUp.isDownRepeating() and isActiveScreen: # Up History
            inc gameState.historyPos
            if gameState.historyPos <= gameState.history.len and gameState.historyPos > 0:
              gameState.input.str = gameState.history[^gameState.historyPos]
              gameState.input.pos = gameState.input.str.len
            else:
              gamestate.input.str = ""
              gameState.input.pos = gameState.input.str.len
            dirtyInput()

          if KeyCodeDown.isDownRepeating() and isActiveScreen: # Down History
            dec gamestate.historyPos
            if gameState.historyPos <= gameState.history.len and gameState.historyPos > 0:
              gameState.input.str = gameState.history[^gameState.historyPos]
              gameState.input.pos = gameState.input.str.len
            else:
              gamestate.input.str = ""
              gameState.input.pos = gameState.input.str.len
            dirtyInput()

          gamestate.historyPos = clamp(gameState.historyPos, 0, gameState.history.len)

          if not gameState.screen.inProgram and dirtiedInput:
            gameState.buffer.clearLine()
            gameState.buffer.put(">")
            if gameState.input.suggestion.len > 0:
              gameState.showInput({WithCursor, WithSuggestion})
            else:
              gameState.showInput()

      else:
        gameState.buffer.hideCursor()
        if gameState.buffer.mode == Text:
          gameState.buffer.clearTo(screen.programY)
          gameState.buffer.cameraPos = screen.programY

        gameState.activeProgramTrait(screen).update(gamestate, dt, true)

      if screen.inProgram and isActiveScreen:
        if KeyCodeEscape.isDown:
          gameState.exitProgram()
          gameState.buffer.put ">"
          gamestate.buffer.showCursor(0)

      gameState.screen = oldScreen
      case screen.action
      of SplitV:
        gameState.splitVertical(screen)
      of SplitH:
        gameState.splitHorizontal(screen)
      of Close:
        gameState.closeScreen(screen)
      of Nothing:
        discard
      if screen.kind == NoSplit:
        screen.action = Nothing
        screen.buffer.upload(dt)

  if gameState.screen.shipStack.len > 0 and startShipCount == gameState.screen.shipStack.len:
    gameState.activeShipEntity.shipData.glyphProperties = gameState.buffer.properties
