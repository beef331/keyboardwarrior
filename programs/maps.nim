{.used.}
import gamestates
import ../screenutils/texttables
import ../data/spaceentity
import std/[algorithm, strutils]
import pkg/truss3D/inputs
import pkg/truss3D

proc formatSpeed(f: float32): string =
  formatFloat(f, ffDecimal, precision = 2)

type
  Map = object

proc name(sensor: Map): string = "Map"
proc onExit(sensor: var Map, gameState: var GameState) = gameState.buffer.mode = Text
proc getFlags(_: Map): ProgramFlags = {}

proc update(sensor: var Map, gameState: var GameState, truss: var Truss, dt: float32, flags: ProgramFlags) =
  if Draw in flags:
    gameState.buffer.clearShapes()
    gamestate.buffer.mode = Graphics
    let player = gameState.activeShipEntity

    gameState.buffer.drawBox(
      gameState.buffer.pixelWidth.float32 / 2,
      gameState.buffer.pixelHeight.float32 / 2,
      10,
      props = GlyphProperties(foreground: parseHtmlColor"yellow", blinkSpeed: 3f)
    )

    gameState.buffer.drawText(
      "You",
      gameState.buffer.pixelWidth / 2,
      gameState.buffer.pixelHeight / 2 + 10,
      0, 0.3
    )

    let sensorRange = gameState.activeShipEntity.sensorRange()

    for entry in gameState.world.allInSensors(gameState.activeShip):

      let
        xDist = entry.x - player.x
        yDist = entry.y - player.y
        realDist = sqrt(xDist * xDist + yDist * yDist)
      if realDist <= sensorRange.float32:
        let
          offsetPos = vec2(gameState.buffer.pixelWidth.float32 / 2, gameState.buffer.pixelHeight.float32 / 2) +
            vec2(xDist, yDist).normalize * ((realDist / sensorRange.float32) * gameState.buffer.pixelHeight.float32)
          x = offsetPos.x
          y = offsetPos.y
          color =
            if entry.kind == Projectile:
              GlyphProperties(foreground: parseHtmlColor"yellow")
            elif entry.faction == Alliance:
              GlyphProperties(foreground: parseHtmlColor"red")
            else:
              gameState.buffer.properties
          size = 3f + 9f * float32(entry.kind != Projectile) + (float32(entry.kind == Station) * 4)

        gameState.buffer.drawBox(x, y, size, props = color)
        if entry.kind != Projectile:
          gameState.buffer.drawText(entry.name & " " & abs(min(xDist, yDist)).formatFloat(ffDecimal, precision = 2), x, y + size, 0, scale = 0.3f, props = color)

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
