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

  TextInput* = object
    str*: string
    pos*: int

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

proc peekInput*(gameState: GameState): TextInput = gameState.input

import programutils
export programutils

importAllCommands()

proc insert(s: var string, at: int, toInsert: string) =
  let appendBuffer = s[at..^1]
  s.setLen(s.len + toInsert.len)
  s[at..at + toInsert.high] = toInsert
  s[at + toInsert.len..^1] = appendBuffer

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

  for command in programutils.commands():
    result.add command

  result.buffer = Buffer(lineWidth: 60, lineHeight: 40, properties: GlyphProperties(foreground: parseHtmlColor("White")))
  result.buffer.initResources("PublicPixel.ttf", true)

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
      gamestate.handlers[command].handler(gameState, input[ind + 1 .. input.high])
    else:
      gameState.writeError("Incorrect command\n")

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

  var dirtiedInput = inputText().len > 0
  if dirtiedInput:
    gameState.input.str.insert gameState.input.pos, inputText()
    gameState.input.pos.inc inputText().len
    setInputText("")

  if KeyCodeBackspace.isDownRepeating() and gameState.input.pos >= 0 and gameState.input.str.len > 0:
    gameState.input.str.delete(gameState.input.pos - 1, gameState.input.pos - 1)
    dec gameState.input.pos
    dirtiedInput = true

  if not gamestate.world.isReady:
    gamestate.buffer.setPosition(0, 0)
    gamestate.buffer.put "Shall we play a game?\n"
    gamestate.buffer.put "Enter your Ship name:\n"
    gameState.buffer.clearLine()
    gameState.buffer.put gameState.input.str

    if KeyCodeReturn.isDownRepeating() and gameState.input.str.len > 0:
      let name = gameState.popInput()
      gameState.shipStack.add name
      gameState.world.init(name, name) # TODO: Take a seed aswell
      gameState.buffer.clearTo(0)
      gameState.buffer.put ">"

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
          gameState.dispatchCommand()
          dirtiedInput = true

        if KeyCodeUp.isDownRepeating(): # Up History
          inc gameState.historyPos
          if gameState.historyPos <= gameState.history.len and gameState.historyPos > 0:
            gameState.input.str = gameState.history[^gameState.historyPos]
            gameState.input.pos = gameState.input.str.len
          else:
            gamestate.input.str = ""
            gameState.input.pos = gameState.input.str.len
          dirtiedInput = true

        if KeyCodeDown.isDownRepeating(): # Down History
          dec gamestate.historyPos
          if gameState.historyPos <= gameState.history.len and gameState.historyPos > 0:
            gameState.input.str = gameState.history[^gameState.historyPos]
            gameState.input.pos = gameState.input.str.len
          else:
            gamestate.input.str = ""
            gameState.input.pos = gameState.input.str.len
          dirtiedInput = true

        gamestate.historyPos = clamp(gameState.historyPos, 0, gameState.history.len)

        if dirtiedInput and not gameState.inProgram:
          gameState.buffer.clearLine()
          gameState.buffer.put(">")
          gameState.buffer.put(gameState.input.str)


    else:
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
