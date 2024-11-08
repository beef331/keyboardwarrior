{.used.}
import gamestates
import std/[strscans, setutils, strbasics, strutils, math]
import "$projectdir"/data/[spaceentity, insensitivestrings]
import "$projectdir"/utils/todoer

type
  HeadingCommand = object
  SpeedCommand = object

proc handler(_: HeadingCommand, gameState: var GameState, input: string) =
  let input = input.strip()
  if input.len == 0:
    gameState.buffer.put($gameState.activeShipEntity.heading)
    gameState.buffer.newLine()
  elif gameState.world.entityExists(input):
    gameState.activeShipEntity.heading = arctan2(
      gameState.world.getEntity(input).y - gameState.activeShipEntity.y,
      gameState.world.getEntity(input).x - gameState.activeShipEntity.x
      )
  else:
    gameState.writeError("No entity named: '" & input & "'.")


proc suggest(_: HeadingCommand, gameState: GameState, input: string, ind: var int): string =
  case input.suggestIndex()
  of 0, 1:
    iterator entities(gameState: GameState): string =
      for ent in gameState.world.allInSensors(gameState.activeShip):
        yield ent.name
    suggestNext(gameState.entities, input, ind)
  else:
    ""


proc name(_: HeadingCommand): string = "heading"
proc help(_: HeadingCommand): string = "Set the heading to the current location of an entity. Prints heading when not provided a target"
proc manual(_: HeadingCommand): string = ""

storeCommand HeadingCommand().toTrait(CommandImpl), {InWorld}


proc handler(_: SpeedCommand, gameState: var GameState, input: string) =
  let input = input.strip()
  if input.len == 0:
    gameState.buffer.put($gameState.activeShipEntity.velocity)
    gameState.buffer.newLine()
  else:
    try:
      let
        f = parseFloat(input)
        maxSpeed = gameState.activeShipEntity.maxSpeed

      if f notin 0f..maxSpeed:
        gameState.writeError("Expected a number in range: '" & $(0f..maxSpeed) & "'.")
      else:
        gameState.activeShipEntity.velocity = f

    except CatchableError:
      gameState.writeError("Expected a number, but got: '" & input & "'.")


proc name(_: SpeedCommand): string = "speed"
proc help(_: SpeedCommand): string = "Set the current speed or prints it out when not provided a speed"
proc manual(_: SpeedCommand): string = ""

proc suggest(_: SpeedCommand, gameState: GameState, input: string, ind: var int): string = ""


storeCommand SpeedCommand().toTrait(CommandImpl), {InWorld}
