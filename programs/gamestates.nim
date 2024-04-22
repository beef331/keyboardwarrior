import ../screenutils/screenrenderer
import pkg/[traitor, chroma, pixie]
import std/[tables, strutils, hashes]
import pkg/truss3D/inputs

export screenrenderer, chroma, pixie

const maxTextSize* = 80

type InsensitiveString* = distinct string
converter toString*(str: InsensitiveString): lent string = string(str)
converter toString*(str: var InsensitiveString): var string = string(str)

proc `==`(a, b: InsensitiveString): bool =
  cmpIgnoreStyle(a, b) == 0

proc hash(str: InsensitiveString): Hash =
  for ch in str.items:
    let ch = ch.toLowerAscii()
    if ch != '_':
      result = result !& hash(ch)

  result = !$result

proc insStr*(s: sink string): InsensitiveString = InsensitiveString(s)

type
  Program* = distinct tuple[
    onExit: proc(_: var Atom, gameState: var GameState) {.nimcall.},
    update: proc(_: var Atom, gameState: var GameState, dt: float32, active: bool) {.nimcall.},
    name: proc(_: Atom): string {.nimcall.}
  ]
  CommandHandler* = proc(gamestate: var Gamestate, input: string)

  Command* = object
    name*: string
    help*: string
    manual*: string # Manpage
    handler*: CommandHandler

  GameState* = object
    buffer*: Buffer
    programs: Table[string, Traitor[Program]]
    activeProgram: string
    handlers: Table[InsensitiveString, Command]
    input: string
    programX: int
    programY: int

implTrait Program

iterator commands*(gameState: GameState): Command =
  for command in gamestate.handlers.values:
    yield command

proc writeError*(gameState: var GameState, msg: string) =
  gameState.buffer.put(msg, GlyphProperties(foreground: parseHtmlColor"red"))

proc enterProgram*(gameState: var GameState, program: Traitor[Program]) =
  (gameState.programX, gameState.programY) = gamestate.buffer.getPosition()
  gameState.buffer.clearTo(gameState.programY)
  gameState.activeProgram = program.name()
  if program.name notin gameState.programs:
    gameState.programs[program.name()] = program

proc enterProgram*(gameState: var GameState, program: sink string) =
  gameState.activeProgram = program

proc hasProgram*(gameState: var GameState, name: string): bool = name in gameState.programs

proc hasCommand*(gameState: var GameState, name: string): bool = InsensitiveString(name) in gameState.handlers
proc getCommand*(gameState: var GameState, name: string): lent Command = gameState.handlers[InsensitiveString(name)]

import programutils
export programutils

importAllCommands()

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
    help: "This toggles 3D view on and off",
    handler: proc(gameState: var GameState, _: string) =
      for i in 1..gameState.buffer.lineHeight:
        gameState.buffer.put $i & repeat("=", gameState.buffer.lineWidth)
        gameState.buffer.newLine()
  )

  result.add Command(
    name: "clear",
    help: "Clears the screen",
    handler: proc(gameState: var GameState, _: string) = gamestate.buffer.toBottom()
  )

  for command in programutils.commands():
    result.add command

  result.buffer = Buffer(lineWidth: 80, lineHeight: 30, properties: GlyphProperties(foreground: parseHtmlColor("White")))
  result.buffer.put(">")
  result.buffer.initResources("PublicPixel.ttf", true)

proc dispatchCommand(gameState: var GameState) =
  let input {.cursor.} = gameState.input
  if input.len > 0:
    let
      ind =
        if (let ind = input.find(' '); ind) != -1:
          ind - 1
        else:
          input.high
      command = insStr input[0..ind]
    if command in gamestate.handlers:
      gamestate.handlers[command].handler(gameState, input[ind + 1 .. input.high])
    else:
      gameState.writeError("Incorrect command\n")
  gameState.input = ""


proc update*(gameState: var GameState, dt: float) =
  for key, program in gamestate.programs:
    if key != gameState.activeProgram:
      program.update(gamestate, dt, false)

  if gamestate.activeProgram == "":
    if isTextInputActive():
      if inputText().len > 0:
        gameState.input.add inputText()
        gameState.buffer.clearLine()
        gameState.buffer.put(">" & gameState.input)
      if KeyCodeReturn.isDownRepeating():
        gameState.buffer.newLine()
        gameState.dispatchCommand()
        gameState.buffer.put(">")
      if KeyCodeBackspace.isDownRepeating() and gameState.input.len > 0:
        gameState.input.setLen(gameState.input.high)
        gameState.buffer.clearLine()
        gameState.buffer.put(">" & gameState.input)

    if KeyCodeUp.isDownRepeating():
      gameState.buffer.scrollUp()

    if KeyCodeDown.isDownRepeating():
      gameState.buffer.scrollDown()
  else:
    gameState.buffer.clearTo(gameState.programY)
    gameState.buffer.cameraPos = gameState.programY
    gameState.programs[gameState.activeProgram].update(gamestate, dt, true)


    if KeyCodeEscape.isDown:
      gameState.buffer.put ">"
      gameState.activeProgram = ""

  gameState.buffer.upload(dt)
  setInputText("")



