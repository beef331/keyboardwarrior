import gamestates

proc helpHandler(gameState: var GameState, input: string) =
  for command in gameState.commands:
    gameState.buffer.put command.name & " - " & command.help
    gameState.buffer.newLine()


const helpCommand* = Command(
  name: "help",
  help: "This prints this message",
  handler: helpHandler
)
