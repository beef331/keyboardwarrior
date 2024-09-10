{.used.}
import gamestates
import ../screenutils/texttables
import ../data/spaceentity
import std/[algorithm, strutils]
import pkg/truss3D/inputs
import pkg/truss3D

proc formatSpeed(f: float32): string =
  formatFloat(f, ffDecimal, precision = 2)

const
  maxZoom = 6f
  zoomSpeed = 3f

type
  Map = object
    zoom: float32 = 1f32
  MapCommand = object

proc name(sensor: Map): string = "Map"
proc onExit(sensor: var Map, gameState: var GameState) = gameState.buffer.mode = Text
proc getFlags(_: Map): ProgramFlags = {}

proc update(map: var Map, gameState: var GameState, truss: var Truss, dt: float32, flags: ProgramFlags) =
  if Draw in flags:
    if TakeInput in flags:
      if truss.inputs.isPressed(KeyCodeLShift) or
        truss.inputs.isPressed(KeyCodeRShift):
        if truss.inputs.isPressed(KeyCodeUp):
          map.zoom -= dt * zoomSpeed
        elif truss.inputs.isPressed(KeyCodeDown):
          map.zoom += dt * zoomSpeed
      map.zoom = clamp(map.zoom, 1, maxZoom)

    let zoom = maxZoom / map.zoom
    gameState.buffer.clearShapes()
    gamestate.buffer.mode = Graphics
    let player = gameState.activeShipEntity

    gameState.buffer.drawBox(
      gameState.buffer.pixelWidth.float32 / 2,
      gameState.buffer.pixelHeight.float32 / 2,
      10 * zoom,
      props = GlyphProperties(foreground: parseHtmlColor"yellow", blinkSpeed: 3f)
    )

    gameState.buffer.drawText(
      "You",
      gameState.buffer.pixelWidth / 2,
      gameState.buffer.pixelHeight / 2 + 10 * zoom,
      0, 0.3 * zoom
    )

    let smallestAxis = min(gameState.buffer.pixelWidth, gameState.buffer.pixelHeight)

    let sensorRange = gameState.activeShipEntity.sensorRange()

    for entry in gameState.world.allInSensors(gameState.activeShip):

      let
        xDist = entry.x - player.x
        yDist = entry.y - player.y
        realDist = sqrt(xDist * xDist + yDist * yDist) * zoom
      if realDist <= sensorRange.float32 * zoom:
        let
          offsetPos = vec2(gameState.buffer.pixelWidth.float32 / 2, gameState.buffer.pixelHeight.float32 / 2) +
            vec2(xDist, yDist).normalize * ((realDist / sensorRange.float32) * (smallestAxis.float32 / 2))
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
        case entry.kind
        of Asteroid:
          gameState.buffer.drawCircle(x, y, (1 + entry.weight / 10) * zoom, props = color)
        else:
          gameState.buffer.drawBox(x, y, size * zoom, props = color)
        if entry.kind != Projectile:
          gameState.buffer.drawText(
            entry.name & " " & abs(min(xDist, yDist)).formatFloat(ffDecimal, precision = 2),
            x, y + size * zoom, 0,
            scale = 0.3f * zoom,
            props = color
          )
        gameState.buffer.drawCircle(
          gameState.buffer.pixelWidth / 2,
          gameState.buffer.pixelHeight / 2,
          smallestAxis.float32 * zoom,
          outline = true
        )

proc handler(_: MapCommand, gameState: var GameState, input: string) =
  if gameState.hasProgram "Map":
    gameState.enterProgram("Map")
  else:
    gameState.enterProgram(Map().toTrait(Program))

proc name(_: MapCommand): string = "map"
proc help(_: MapCommand): string = "Shows nearby ships and points of interest"
proc manual(_: MapCommand): string = ""
proc suggest(_: MapCommand, gameState: GameState, input: string, ind: var int): string = discard

storeCommand MapCommand().toTrait(CommandImpl)
