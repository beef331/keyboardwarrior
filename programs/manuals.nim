import gamestates, eventprinter
import std/strscans

proc manualHandler(gameState: var GameState, input: string) =
  var command = ""
  if input.scanf("$s$+", command) and gameState.hasCommand(command):
    let start = gameState.buffer.getPosition()[1]
    gameState.buffer.displayEvent(gameState.getCommand(command).manual, false)


  else:
    gameState.writeError("Expected `man commandName`\n")


command(
  "man",
  "Tool for reading more about what a command does",
  manualHandler
)
