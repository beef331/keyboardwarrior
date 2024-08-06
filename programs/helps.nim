import gamestates

proc helpHandler(gameState: var GameState, input: string) =
  for command in gameState.commands:
    var props = gameState.buffer.properties
    props.foreground = props.foreground / 2
    gameState.buffer.put(command.name, props = props)
    gameState.buffer.put(": " & command.help, wrapped = true)
    gameState.buffer.newLine()


command(
  "help",
  "This prints this message",
  helpHandler
)
