{.used.}
import gamestates, eventprinter
import std/strscans

type ManPage = object

proc name(_: ManPage): string = "manual"
proc onExit(_: var ManPage, gameState: var GameState) = discard
proc update(_: var ManPage, gameState: var GameState, dt: float32, _: ProgramFlags) = discard
proc getFlags(_: ManPage): ProgramFlags = {Blocking}


proc manualHandler(gameState: var GameState, input: string) =
  var command = ""
  if input.scanf("$s$+", command) and gameState.hasCommand(command):
    if gamestate.hasProgram("manual"):
      gameState.enterProgram("manual")
    else:
      gameState.enterProgram(Manpage().toTrait Program)
    let start = gameState.buffer.getPosition()[1]
    gameState.buffer.displayEvent(gameState.getCommand(command).manual, false)

  else:
    gameState.writeError("Expected `man commandName`\n")




command(
  "man",
  "Tool for reading more about what a command does",
  manualHandler
)
