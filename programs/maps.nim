import gamestates
import ../screenutils/texttables
import ../data/spaceentity
import std/[algorithm, strutils]
import pkg/truss3D/inputs

proc formatSpeed(f: float32): string =
  formatFloat(f, ffDecimal, precision = 2)

type
  Map = object

proc name(sensor: Map): string = "Map"
proc onExit(sensor: var Map, gameState: var GameState) = gameState.buffer.mode = Text
proc getFlags(_: Map): ProgramFlags = {}

proc update(sensor: var Map, gameState: var GameState, dt: float32, active: bool) =
  if active:
    gameState.buffer.clearShapes()
    gamestate.buffer.mode = Graphics
    let player = gameState.world.player

    gameState.buffer.drawBox(
      gameState.buffer.pixelWidth.float32 / 2,
      gameState.buffer.pixelHeight.float32 / 2,
      31,
      props = GlyphProperties(foreground: parseHtmlColor"yellow", blinkSpeed: 3f)
    )

    gamestate.buffer.drawRect(
      gameState.buffer.pixelWidth.float32 / 2, gameState.buffer.pixelHeight.float32 / 2,
      1f, float32 gameState.buffer.pixelHeight,
      props = GlyphProperties(foreground: parseHtmlColor"orange")
    )


    gamestate.buffer.drawRect(
      gameState.buffer.pixelWidth.float32 / 2, gameState.buffer.pixelHeight.float32 / 2,
      float32 gameState.buffer.pixelWidth, 1f,
      props = GlyphProperties(foreground: parseHtmlColor"orange")
    )


    gameState.buffer.drawText(
      "You",
      gameState.buffer.pixelWidth / 2,
      gameState.buffer.pixelHeight / 2 + 32,
      0, 1
    )

    let sensorRange = gameState.activeShipEntity.sensorRange()

    for entry in gameState.world.allInSensors(gameState.activeShip):
      break
      let
        xDist = entry.x - player.x
        yDist = entry.y - player.y
        realDist = sqrt(xDist * xDist + yDist * yDist)
        x = gameState.buffer.pixelWidth.float32 / 2
        y = gameState.buffer.pixelHeight.float32 / 2
        color =
          if entry.faction == Alliance:
            GlyphProperties(foreground: parseHtmlColor"red")
          else:
            gameState.buffer.properties

      gameState.buffer.drawBox(x, y, 32, props = color)
      gameState.buffer.drawText(entry.name & " " & $abs(min(xDist, yDist)), x, y + 64f, 0, scale = 0.3f, props = color)

proc sensorHandler(gameState: var GameState, input: string) =
  if gameState.hasProgram "Map":
    gameState.enterProgram("Map")
  else:
    gameState.enterProgram(Map().toTrait(Program))

command(
  "map",
  "Prints out information of nearby ships and points of interest",
  sensorHandler
)