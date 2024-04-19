import gamestates

proc helpHandler(gameState: var GameState, input: string) =
  for command in gameState.commands:
    gameState.buffer.put command.name & " - " & command.help
    gameState.buffer.newLine()


command(
  "help",
  "This prints this message",
  helpHandler
)
