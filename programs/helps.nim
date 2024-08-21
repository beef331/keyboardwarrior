{.used.}
import gamestates

type Help = object

proc name(_: Help): string = "help"
proc help(_: Help): string = "This prints this message"
proc manual(_: Help): string = ""
proc handler(_: Help, gameState: var GameState, input: string) =
  for command in gameState.commands:
    var props = gameState.buffer.properties
    props.foreground = props.foreground / 2
    gameState.buffer.put(command.name(), props = props)
    gameState.buffer.put(": " & command.help, wrapped = true)
    gameState.buffer.newLine()


proc suggest(_: Help, gs: GameState, input: string, ind: var int): string = discard

storeCommand Help().toTrait(CommandImpl)
