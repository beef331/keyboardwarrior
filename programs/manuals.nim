{.used.}
import gamestates, eventprinter
import std/strscans
import pkg/truss3D

type
  ManPage = object
  ManCommand = object

proc name(_: ManPage): string = "manual"
proc onExit(_: var ManPage, gameState: var GameState) = discard
proc update(_: var ManPage, gameState: var GameState, _: var Truss, dt: float32, _: ProgramFlags) = discard
proc getFlags(_: ManPage): ProgramFlags = {Blocking}


proc handler(_: ManCommand, gameState: var GameState, input: string) =
  var command = ""
  if input.scanf("$s$+", command) and gameState.hasCommand(command):
    if gameState.getCommand(command).manual != "":
      if gamestate.hasProgram("manual"):
        gameState.enterProgram("manual")
      else:
        gameState.enterProgram(Manpage().toTrait Program)
      let start = gameState.buffer.getPosition()[1]
      gameState.buffer.displayEvent(gameState.getCommand(command).manual, false)
    else:
      gameState.writeError($command & "has not manual.")

  else:
    gameState.writeError("Expected `man commandName`.")

proc name(_: ManCommand): string = "man"
proc help(_: ManCommand): string = "Tool for reading more about what a command does"
proc manual(_: ManCommand): string = ""

proc suggest(_: ManCommand, gameState: GameState, input: string, ind: var int): string = discard

storeCommand ManCommand().toTrait(CommandImpl)
