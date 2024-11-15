{.used.}
import gamestates, screens
import std/strutils
import ../data/insensitivestrings

type
  DebugCommand = object
  ExitCommand = object
  ClearCommand = object
  ProgramCommand = object
  SplitVCommand = object
  SplitHCommand = object
  CloseCommand = object


proc name(_: DebugCommand): string = "debug"
proc help(_: DebugCommand): string = "Prints lines for debugging the buffer"
proc manual(_: DebugCommand): string = ""
proc handler(_: DebugCommand, gameState: var GameState, input: string) =
  for i in 1..gameState.buffer.lineHeight:
    gameState.buffer.put $i & repeat("=", gameState.buffer.lineWidth)
    gameState.buffer.newLine()


proc suggest(_: DebugCommand, gs: GameState, input: string, ind: var int): string = discard

storeCommand DebugCommand().toTrait(CommandImpl)


proc name(_: ExitCommand): string = "exit"
proc help(_: ExitCommand): string = "This prints this message"
proc manual(_: ExitCommand): string = ""
proc handler(_: ExitCommand, gameState: var GameState, input: string) =
  if input == "player":
    gameState.screen.shipStack.setLen(1)
  elif gameState.screen.shipStack.len > 1:
    gameState.buffer.properties = gameState.getEntity(gameState.screen.shipStack[^2]).shipData.glyphProperties
    gameState.buffer.put("Exited: " & gameState.activeShipEntity.name & "\n")
    gameState.screen.shipStack.setLen(gameState.screen.shipStack.high)
  else:
    gameState.buffer.put("Where do you want to go,")
    gameState.buffer.put(" SPACE?\n", GlyphProperties(
      foreground: gameState.buffer.properties.foreground,
      background: gameState.buffer.properties.background,
      shakeStrength: 5, shakeSpeed: 30)
    )


proc suggest(_: ExitCommand, gs: GameState, input: string, ind: var int): string = discard

storeCommand ExitCommand().toTrait(CommandImpl), {InWorld}

proc name(_: ClearCommand): string = "clear"
proc help(_: ClearCommand): string = "Clears the screen"
proc manual(_: ClearCommand): string = ""
proc handler(_: ClearCommand, gameState: var GameState, input: string) =
  gamestate.buffer.toBottom()
proc suggest(_: ClearCommand, gs: GameState, input: string, ind: var int): string = discard

storeCommand ClearCommand().toTrait(CommandImpl)

proc name(_: ProgramCommand): string = "programs"
proc help(_: ProgramCommand): string = "Lists all running programs for the current ship"
proc manual(_: ProgramCommand): string = ""
proc handler(_: ProgramCommand, gameState: var GameState, input: string) =
  if input.isEmptyOrWhitespace():
    for name in gameState.activeProgramsByName:
      gameState.buffer.put(name)
      gameState.buffer.newLine()

  else:
    gameState.enterProgram InsensitiveString input.strip()

proc suggest(_: ProgramCommand, gameState: GameState, input: string, ind: var int): string =
  iterator programsIter(gameState: GameState): string =
    for key in gameState.activeProgramsByName:
      yield string key
  case input.suggestIndex()
  of 0, 1:
    suggestNext(gameState.programsIter, input, ind)
  else:
    ""
storeCommand ProgramCommand().toTrait(CommandImpl)

proc name(_: SplitVCommand): string = "splitv"
proc help(_: SplitVCommand): string = "Splits the current terminal vertically. The left side maintains history"
proc manual(_: SplitVCommand): string = ""
proc handler(_: SplitVCommand, gameState: var GameState, input: string) =
  let size =
    try:
      parseFloat(input.strip())
    except:
      0.5

  if gameState.buffer.lineWidth.float32 * size < 10:
    gameState.writeError("Cannot make the buffer, width would be too small")
    return
  gameState.screen.splitPercentage = size
  gameState.screen.action = SplitV

proc suggest(_: SplitVCommand, gs: GameState, input: string, ind: var int): string = discard

storeCommand SplitVCommand().toTrait(CommandImpl)

proc name(_: SplitHCommand): string = "splith"
proc help(_: SplitHCommand): string = "Splits the current terminal horizontally. The top side maintains history"
proc manual(_: SplitHCommand): string = ""
proc handler(_: SplitHCommand, gameState: var GameState, input: string) =
  let size =
    try:
      parseFloat(input.strip())
    except:
      0.5

  if gameState.buffer.lineHeight.float32 * size < 10:
    gameState.writeError("Cannot make the buffer, height would be too small")
    return
  gameState.screen.splitPercentage = size
  gameState.screen.action = SplitH

proc suggest(_: SplitHCommand, gs: GameState, input: string, ind: var int): string = discard

storeCommand SplitHCommand().toTrait(CommandImpl)


proc name(_: CloseCommand): string = "close"
proc help(_: CloseCommand): string = "Closes the active window if it is not the last opened window."
proc manual(_: CloseCommand): string = ""
proc handler(_: CloseCommand, gameState: var GameState, input: string) =
  assert gameState.screen.kind == NoSplit
  gameState.screen.action = Close

proc suggest(_: CloseCommand, gs: GameState, input: string, ind: var int): string = discard

storeCommand CloseCommand().toTrait(CommandImpl)
