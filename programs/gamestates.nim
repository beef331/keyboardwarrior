import ../screenutils/screenrenderer
import ../data/[spaceentity, insensitivestrings]
import pkg/[traitor, chroma, pixie]
import std/[tables, strutils, hashes, random]
import pkg/truss3D/inputs

export screenrenderer, chroma, pixie

const maxTextSize* = 80

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


  GameState* = object
    buffer*: Buffer

    shipStack: seq[string] ## Stack of names for which ship is presently controlled
      ## [^1] is active
      ## [0] is the player's

    programs: Table[InsensitiveString, Traitor[Program]]
    activeProgram: InsensitiveString
    handlers: Table[InsensitiveString, Command]

    history: seq[string]
    historyPos: int

    programX: int
    programY: int
    world*: World


    fpsX, fpsY: int # Where we write to
    lastFpsBuffer: seq[Glyph]

    input: TextInput

    curveAmount*: float32 # The curve amount

implTrait Program

iterator commands*(gameState: GameState): Command =
  for command in gamestate.handlers.values:
    yield command

proc writeError*(gameState: var GameState, msg: string) =
  gameState.buffer.put(msg, GlyphProperties(foreground: parseHtmlColor"red"))

proc activeShip*(gameState: GameState): lent string = gameState.shipStack[gameState.shipStack.high]

proc activeShipEntity*(gameState: GameState): lent SpaceEntity =
  gameState.world.getEntity(gameState.activeShip)

proc activeShipEntity*(gameState: var GameState): var SpaceEntity =
  gameState.world.getEntity(gameState.activeShip)

proc enterProgram*(gameState: var GameState, program: Traitor[Program]) =
  (gameState.programX, gameState.programY) = gamestate.buffer.getPosition()
  gameState.buffer.clearTo(gameState.programY)

  let programName = InsensitiveString gameState.activeShip & program.name()
  gameState.activeProgram = programName

  if programName notin gameState.programs:
    gameState.programs[programName] = program

proc enterProgram*(gameState: var GameState, program: sink string) =
  let programName = gameState.activeShip & program
  gameState.activeProgram = InsensitiveString programName

proc exitProgram*(gameState: var GameState) =
  gameState.programs[gameState.activeProgram].onExit(gameState)
  gameState.activeProgram = insStr""
  gameState.buffer.put ">"
  gamestate.buffer.showCursor(0)
  gameState.input.pos = 0
  gameState.input.str.setLen(0)

proc hasProgram*(gameState: var GameState, name: string): bool = name.InsensitiveString in gameState.programs

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
  result = gameState.world.entityExists(name) and name != gameState.shipStack[^1] # O(N) Send help!
  if result:
    gameState.shipStack.add name
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
        gameState.shipStack.setLen(1)
      elif gameState.shipStack.len > 1:
        gameState.buffer.properties = gameState.getEntity(gameState.shipStack[^2]).shipData.glyphProperties
        gameState.buffer.put("Exited: " & gameState.activeShip & "\n")
        gameState.shipStack.setLen(gameState.shipStack.high)
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

  for command in programutils.commands():
    result.add command

  result.buffer = Buffer(lineWidth: 60, lineHeight: 40, properties: GlyphProperties(foreground: parseHtmlColor("White")))
  result.buffer.initResources("PublicPixel.ttf", true)

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


proc inProgram(gameState: GameState): bool = gameState.activeProgram != ""
proc currentProgramFlags(gameState: GameState): ProgramFlags =
  if gameState.inProgram:
    gameState.programs[gameState.activeProgram].getFlags()
  else:
    {}

proc update*(gameState: var GameState, dt: float) =
  let
    props = gameState.buffer.properties
    startCount = gameState.shipStack.len

  if gameState.shipStack.len > 0:
    gameState.buffer.properties = gameState.activeShipEntity.shipData.glyphProperties

  if gameState.buffer.mode == Text:
    gamestate.buffer.withPos(gameState.fpsX, gameState.fpsY):
      gameState.buffer.put gameState.lastFpsBuffer

  var dirtiedInput = false

  proc dirtyInput() = dirtiedInput = true

  if inputText().len > 0:
    gameState.input.str.insert gameState.input.pos, inputText()
    gameState.input.pos.inc inputText().len
    setInputText("")
    gameState.clearSuggestion()
    dirtyInput()


  if KeyCodeBackspace.isDownRepeating() and gameState.input.pos > 0 and gameState.input.str.len > 0:
    gameState.input.str.delete(gameState.input.pos - 1 .. gameState.input.pos - 1)
    dec gameState.input.pos
    gameState.clearSuggestion()
    dirtyInput()


  if KeycodeLeft.isDownRepeating:
    gameState.input.pos = max(gameState.input.pos - 1, 0)

  if KeycodeRight.isDownRepeating:
    if gameState.input.suggestionInd != -1:
      gameState.takeSuggestion()
    else:
      gameState.input.pos = min(gameState.input.pos + 1, gameState.input.str.len)


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
      gameState.shipStack.add name
      gameState.world.init(name, name) # TODO: Take a seed aswell
      gameState.buffer.clearTo(0)
      gameState.buffer.put ">"
      gameState.showInput()


  else:
    gamestate.world.update(dt)


    for key, program in gamestate.programs:
      if key != gameState.activeProgram:
        program.update(gamestate, dt, false)

    if not gamestate.inProgram or Blocking in gamestate.currentProgramFlags:
      if KeyCodePageUp.isDownRepeating(): # Scrollup
        gameState.buffer.scrollUp()

      if KeyCodePageDown.isDownRepeating(): # Scroll Down
        gameState.buffer.scrollDown()

      if Blocking notin gameState.currentProgramFlags:
        if KeyCodeReturn.isDownRepeating(): # Enter
          if gameState.input.suggestion.len > 0:
            gameState.takeSuggestion()
          else:
            gameState.dispatchCommand()
          dirtyInput()

        if KeyCodeUp.isDownRepeating(): # Up History
          inc gameState.historyPos
          if gameState.historyPos <= gameState.history.len and gameState.historyPos > 0:
            gameState.input.str = gameState.history[^gameState.historyPos]
            gameState.input.pos = gameState.input.str.len
          else:
            gamestate.input.str = ""
            gameState.input.pos = gameState.input.str.len
          dirtyInput()

        if KeyCodeDown.isDownRepeating(): # Down History
          dec gamestate.historyPos
          if gameState.historyPos <= gameState.history.len and gameState.historyPos > 0:
            gameState.input.str = gameState.history[^gameState.historyPos]
            gameState.input.pos = gameState.input.str.len
          else:
            gamestate.input.str = ""
            gameState.input.pos = gameState.input.str.len
          dirtyInput()

        gamestate.historyPos = clamp(gameState.historyPos, 0, gameState.history.len)

        if not gameState.inProgram and dirtiedInput:
          gameState.buffer.clearLine()
          gameState.buffer.put(">")
          if gameState.input.suggestion.len > 0:
            gameState.showInput({WithCursor, WithSuggestion})
          else:
            gameState.showInput()

    else:
      gameState.buffer.hideCursor()
      if gameState.buffer.mode == Text:
        gameState.buffer.clearTo(gameState.programY)
        gameState.buffer.cameraPos = gameState.programY

      gameState.programs[gameState.activeProgram].update(gamestate, dt, true)

    if gameState.inProgram:
      if KeyCodeEscape.isDown:
        gameState.exitProgram()


  let chars = " fps: " & (1f / dt).formatFloat(format = ffDecimal, precision = 2)
  gamestate.fpsX = gameState.buffer.lineWidth - chars.len
  gamestate.fpsY = gameState.buffer.cameraPos

  if gameState.buffer.mode == Text:
    gameState.buffer.withPos(gameState.fpsX, gamestate.fpsY):
      gameState.lastFpsBuffer = gameState.buffer.fetchAndPut(chars, false)
  else:
    gameState.buffer.drawText(chars, 0f, gameState.buffer.pixelHeight.float32 * 2)

  gameState.buffer.upload(dt)

  if gameState.shipStack.len > 0 and startCount == gameState.shipStack.len:
    gameState.activeShipEntity.shipData.glyphProperties = gameState.buffer.properties

  gameState.buffer.properties = props
