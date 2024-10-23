{.used.}
import gamestates
import std/[strscans, setutils, strbasics, strformat]
import "$projectdir"/data/[spaceentity, insensitivestrings, worlds]
import "$projectdir"/utils/todoer

type
  Combat = object
  Fire = object

proc handler(_: Combat, gameState: var GameState, input: string) =
  if (var (success, target) = input.scanTuple("$s$+"); success):
    target.strip()
    if gameState.hasEntity(target, {Ship, Station}):
      gameState.world.enterCombat(gameState.activeShip, target)
    else:
      gameState.writeError(fmt"No ship or station named: '{target}' found.")
  else:
    gameState.writeError("Expected: 'combat target'.")

proc suggest(_: Combat, gameState: GameState, input: string, ind: var int): string =
  case input.suggestIndex()
  of 0, 1:
    iterator allShips(gameState: GameState): string =
      for ent in gameState.world.allInSensors(gameState.activeShip):
        if ent.kind in {Ship, Station}:
          yield ent.name
    suggestNext(gameState.allShips(), input, ind)
  else:
    ""

proc name(_: Combat): string = "combat"
proc help(_: Combat): string = "Start combat with a ship or station"
proc manual(_: Combat): string = ""

storeCommand Combat().toTrait(CommandImpl)
