{.used.}
import gamestates
import std/strutils
import "$projectdir"/data/[spaceentity, insensitivestrings]

type Scanner = object

proc name(_: Scanner): string = "scanner"
proc help(_: Scanner): string = "Scans nearby ships, asteroids, stations, and ore processors"
proc manual(_: Scanner): string = ""
proc handler(_: Scanner, gameState: var GameState, input: string) =
  let input = InsensitiveString input.strip()

  if gameState.entityExists(input):
    let ent = gameState.world.getEntity(input)
    case ent.kind
    of Asteroid:
      for x in ent.resources:
        gameState.buffer.put x.entry.name
        gameState.buffer.put " - Amount: "
        gameState.buffer.put $x.amount
        gameState.buffer.put " - Weight: "
        gameState.buffer.put $(x.amount * x.entry.weight)
        gameState.buffer.newLine()
    of OreProcessor:
      for (cost, entry) in ent.smeltOptions.items:
        gameState.buffer.put "$"
        gameState.buffer.put $cost
        gameState.buffer.put " per "
        gameState.buffer.put entry.name
        gamestate.buffer.newLine()
    else:
      discard
  else:
    gameState.writeError("Cannot find any entity named: '" & input & "'.")


proc suggest(_: Scanner, gameState: GameState, input: string, ind: var int): string =
  case input.suggestIndex()
  of 0, 1:
    iterator entities(gameState: GameState): string =
      for ent in gameState.world.allInSensors(gameState.activeShip):
        yield ent.name
    suggestNext(gameState.entities, input, ind)
  else:
    ""


storeCommand Scanner().toTrait(CommandImpl), {InWorld}
