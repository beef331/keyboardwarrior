import ../screenutils/screenrenderer
import ../data/[spaceentity, insensitivestrings, worlds]
import pkg/[chroma, pixie, truss3D, traitor]
import std/[tables, strutils, hashes, random, setutils]
import pkg/truss3D/[inputs]
import screens

export screenrenderer, chroma, pixie

const ShellCarrot* = ">"

type
  ProgramFlag* = enum
    Blocking ## For things like manpage, no need to clear just do not print `> ...` next
    Draw ## Passed to tell the program it's drawing
    TakeInput ## Passed to tell the program it's currently the interacted screen

  ProgramFlags* = set[ProgramFlag]

  Program* = distinct tuple[
    onExit: proc(_: var Atom, gameState: var GameState) {.nimcall.},
    update: proc(_: var Atom, gameState: var GameState, truss: var Truss, dt: float32, active: ProgramFlags) {.nimcall.},
    name: proc(_: Atom): string {.nimcall.},
    getFlags: proc(_: Atom): set[ProgramFlag] {.nimcall.},
  ]

  CommandImpl* = distinct tuple[
    name: proc(_: Atom): string {.nimcall.},
    help: proc(_: Atom): string {.nimcall.},
    manual: proc(_: Atom): string {.nimcall.},
    handler:  proc(_: Atom, gamestate: var Gamestate, input: string) {.nimcall.},
    suggest: proc(_: Atom, gs: GameState, input: string, ind: var int): string {.nimcall.}
  ]

  InputShow = enum
    WithCursor
    WithSuggestion

  GameState* = object
    rootScreen: Screen
    screen*: Screen
    screenCount: int

    programs: Table[ControlledEntity, Table[InsensitiveString, Traitor[Program]]]

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
  Command* = Traitor[CommandImpl]


implTrait Program
implTrait CommandImpl

var defaultHandlers*: array[EntityState, Table[InsensitiveString, Command]]

iterator activeProgramsByName*(gameState: GameState): lent string =
  let controlledEnt = gameState.screen.shipStack[^1]
  if controlledEnt in gamestate.programs:
    for k, v in gameState.programs[controlledEnt]:
      yield string(k)



iterator screens*(gameState: var GameState): Screen =
  for screen in gameState.rootScreen.screens:
    yield screen

proc input(gameState: GameState): lent TextInput = gameState.screen.input
proc input(gameState: var GameState): var TextInput = gameState.screen.input

proc buffer*(gameState: var GameState): var Buffer =
  gameState.screen.buffer

proc writeError*(gameState: var GameState, msg: string) =
  gameState.buffer.put(msg, GlyphProperties(foreground: parseHtmlColor"red"))
  gameState.buffer.newLine()

proc activeShip*(gameState: GameState): ControlledEntity =
  gameState.screen.shipStack[^1]

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

proc enterProgram*(gameState: var GameState, program: InsensitiveString) =
  if gameState.screen.shipStack[^1] in gameState.programs and program in gameState.programs[gameState.screen.shipStack[^1]]:
    gameState.screen.activeProgram = program
  else:
    gameState.writeError("No program found for active ship named: " & $program)

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

proc defaultCommands(gameState: GameState): lent Table[InsensitiveString, Command] =
  defaultHandlers[gameState.activeShipEntity.state]


iterator commands*(gameState: GameState): Command =
  for command in gameState.defaultCommands().values:
    yield command

proc hasCommand*(gameState: var GameState, name: string): bool = InsensitiveString(name) in gameState.defaultCommands()
proc getCommand*(gameState: var GameState, name: string): Command = gameState.defaultCommands()[InsensitiveString(name)]

proc entityExists*(gameState: var GameState, name: string): bool =
  let loc = gamestate.screen.shipStack[^1].location
  gameState.world.entityExists(loc, name)

proc getEntity*(gameState: GameState, entity: ControlledEntity): lent SpaceEntity =
  gameState.world.getEntity(entity)

proc getEntity*(gameState: var GameState, entity: ControlledEntity): var SpaceEntity =
  gameState.world.getEntity(entity)

proc hasEntity*(gameState: GameState, name: string, kind: set[EntityKind] = EntityKind.fullset): bool =
  let loc = gamestate.screen.shipStack[^1].location
  gameState.world.hasEntity(loc, name, kind)

proc getEntity*(gameState: GameState, name: string): lent SpaceEntity =
  let loc = gamestate.screen.shipStack[^1].location
  gameState.world.getEntity(loc, name)

proc getEntity*(gameState: var GameState, name: string): var SpaceEntity =
  let loc = gamestate.screen.shipStack[^1].location
  gameState.world.getEntity(loc, name)

proc takeControlOf*(gameState: var GameState, name: string): bool =
  ## takes control of a ship returning true if it can be found and connected to
  let loc = gamestate.screen.shipStack[^1].location
  result = gameState.world.entityExists(loc, name) and name != gamestate.activeShipEntity.name # O(N) Send help!
  if result:
    gameState.screen.shipStack.add ControlledEntity(location: loc, entryId: gamestate.world.getEntityId(loc, name))
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

import
  helps, eventprinter, manuals, shops, statuses, sensors, textconfig, auxiliarycommands, combats

proc splitVertical(gameState: var GameState, screen: Screen) =
  screen.action = Nothing
  screen.buffer.setLineWidth screen.buffer.lineWidth div 2
  var buff = Buffer(
    lineWidth: screen.buffer.lineWidth,
    lineHeight: screen.buffer.lineHeight
  )
  buff.initFrom(gamestate.screen.buffer)
  buff.put(ShellCarrot)
  buff.showCursor(0)

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
  )
  buff.initFrom(gamestate.screen.buffer)
  buff.put(ShellCarrot)
  buff.showCursor(0)
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
  if gameState.screen == gameState.rootScreen:
    gameState.writeError("You cannot leave your own ship")
  else:
    screen.action = Nothing
    let
      theParent = screen.parent
      theSplit = move screen.parent[]


    theParent[] =
      if screen == theSplit.left:
        move theSplit.right[]
      elif screen == theSplit.right:
        move theSplit.left[]
      else:
        raiseAssert "Unreachable screen has to be left or right of it's parent"

    if theParent.kind != NoSplit:
      theParent.left.parent = theParent
      theParent.right.parent = theParent

    theParent.x = theSplit.x
    theParent.y = theSplit.y
    theParent.w = theSplit.w
    theParent.h = theSplit.h

    gameState.screen = theParent

    theParent.parent = theSplit.parent

    if theParent.kind != NoSplit:
      gameState.screen = theParent.left

    theParent.recalculate()

    dec gameState.screenCount


proc focus(gameState: var Gamestate, dir: FocusDirection) =
  gameState.screen = gameState.rootScreen.focus(gameState.screen, dir)

proc init*(_: typedesc[GameState]): GameState =
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
    if command in gameState.defaultCommands():
      gameState.clearSuggestion()
      gameState.defaultCommands()[command.InsensitiveString].handler(gameState, input[ind + 1 .. input.high])
    else:
      gameState.writeError("Incorrect command")


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
    if command in gameState.defaultCommands():
      gameState.input.suggestion = gameState.defaultCommands()[command].suggest(gameState, input[ind + 1 .. input.high], gameState.input.suggestionInd)
  else: # We search top level commands
    iterator handlerStrKeys(gameState: GameState): string =
      for key in gameState.defaultCommands().keys:
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

proc recalculateScreens*(gameState: var GameState) =
  gameState.rootScreen.recalculate()

proc update*(gameState: var GameState, truss: var Truss, dt: float) =

  var dirtiedInput = false
  proc dirtyInput() = dirtiedInput = true

  let lAltPressed = truss.inputs.isPressed(KeycodeLAlt)

  if lAltPressed:
    if truss.inputs.isDownRepeating(KeyCodeUp):
      gameState.focus(Up)
      dirtyInput()
    if truss.inputs.isDownRepeating(KeyCodeRight):
      gameState.focus(Right)
      dirtyInput()
    if truss.inputs.isDownRepeating(KeyCodeDown):
      gameState.focus(Down)
      dirtyInput()
    if truss.inputs.isDownRepeating(KeyCodeLeft):
      gameState.focus(Left)
      dirtyInput()

  if truss.inputs.inputText().len > 0:
    gameState.input.str.insert truss.inputs.inputText(), gameState.input.pos
    gameState.input.pos.inc truss.inputs.inputText().len
    truss.inputs.setInputText("")
    gameState.clearSuggestion()
    dirtyInput()


  let startShipCount = gameState.screen.shipStack.len

  if startShipCount > 0:
    gameState.buffer.properties = gameState.activeShipEntity.shipData.glyphProperties

  if truss.inputs.isDownRepeating(KeyCodeBackspace) and gameState.input.pos > 0 and gameState.input.str.len > 0:
    gameState.input.str.delete(gameState.input.pos - 1 .. gameState.input.pos - 1)
    dec gameState.input.pos
    gameState.clearSuggestion()
    dirtyInput()


  if truss.inputs.isDownRepeating(KeyCodeLeft) and not lAltPressed:
    gameState.input.pos = max(gameState.input.pos - 1, 0)
    dirtyInput()


  if truss.inputs.isDownRepeating(KeyCodeRight) and not lAltPressed:
    if gameState.input.suggestionInd != -1:
      gameState.takeSuggestion()
    else:
      gameState.input.pos = min(gameState.input.pos + 1, gameState.input.str.len)
    dirtyInput()



  if truss.inputs.isDownRepeating(KeycodeTab):
    if truss.inputs.isPressed(KeyCodeLShift) or truss.inputs.isPressed(KeyCodeRShift):
      dec gameState.input.suggestionInd, 2
    gameState.suggest()
    dirtyInput()


  if not gamestate.world.isReady:
    gamestate.buffer.setPosition(0, 0)
    gamestate.buffer.put "Shall we play a game?\n"
    gamestate.buffer.put "Enter your Ship name:\n"
    gameState.buffer.clearLine()
    gameState.showInput()

    if truss.inputs.isDownRepeating(KeycodeReturn)and gameState.input.str.len > 0:
      let name = gameState.popInput()
      gameState.screen.shipStack.add ControlledEntity(location: LocationId(0), entryId: 0) # Player is always first entity made
      gameState.world.init(name, name) # TODO: Take a seed aswell
      gameState.buffer.clearTo(0)
      gameState.buffer.put ShellCarrot
      gameState.showInput()

    gameState.screen.buffer.upload(dt, truss.windowSize.vec2)
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
          program.update(gamestate, truss, dt, {})


    for screen in gamestate.screens:
      let
        isActiveScreen = gameState.screen == screen
        oldScreen = gameState.screen
      gameState.screen = screen

      if not screen.inProgram or Blocking in gameState.currentProgramFlags(gameState.screen):
        if truss.inputs.isDownRepeating(KeycodePageUp) and isActiveScreen: # Scrollup
          gameState.buffer.scrollUp()

        if truss.inputs.isDownRepeating(KeycodePageDown) and isActiveScreen: # Scroll Down
          gameState.buffer.scrollDown()

        if Blocking notin gameState.currentProgramFlags(gameState.screen):
          if truss.inputs.isDownRepeating(KeyCodeReturn) and isActiveScreen: # Enter
            if gameState.input.suggestion.len > 0:
              gameState.takeSuggestion()
            else:
              gameState.dispatchCommand()
            dirtyInput()

          if truss.inputs.isDownRepeating(KeyCodeUp) and isActiveScreen and not lAltPressed: # Up History
            inc gameState.historyPos
            if gameState.historyPos <= gameState.history.len and gameState.historyPos > 0:
              gameState.input.str = gameState.history[^gameState.historyPos]
              gameState.input.pos = gameState.input.str.len
            else:
              gamestate.input.str = ""
              gameState.input.pos = gameState.input.str.len
            dirtyInput()

          if truss.inputs.isDownRepeating(KeyCodeDown) and isActiveScreen and not lAltPressed: # Down History
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
            gameState.buffer.put(ShellCarrot)
            if gameState.input.suggestion.len > 0:
              gameState.showInput({WithCursor, WithSuggestion})
            else:
              gameState.showInput()

      else:
        gameState.buffer.hideCursor()
        if gameState.buffer.mode == Text:
          gameState.buffer.clearTo(screen.programY)
          gameState.buffer.cameraPos = screen.programY
        let flag =
          if screen == oldScreen:
            {Draw, TakeInput}
          else:
            {Draw}

        gameState.activeProgramTrait(screen).update(gamestate, truss, dt, flag)

      if screen.inProgram and isActiveScreen:
        if truss.inputs.isDown(KeyCodeEscape):
          gameState.exitProgram()
          gameState.buffer.put ShellCarrot
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
        screen.buffer.upload(dt, truss.windowSize.vec2)


  if gameState.screen.shipStack.len > 0 and startShipCount == gameState.screen.shipStack.len:
    gameState.activeShipEntity.shipData.glyphProperties = gameState.buffer.properties
