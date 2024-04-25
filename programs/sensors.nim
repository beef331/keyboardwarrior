import gamestates
import ../screenutils/texttables
import ../data/spaceentity
import std/[algorithm, strutils]

proc formatSpeed(f: float32): string =
  formatFloat(f, ffDecimal, precision = 2)

type
  Sensor = object
  Entry = object
    name: string
    x {.tableStringify(formatSpeed).}: float32
    y {.tableStringify(formatSpeed).}: float32
    distance {.tableStringify(formatSpeed).}: float32
    speed {.tableStringify(formatSpeed).}: float32
    faction: Faction

proc name(sensor: Sensor): string = "Sensor"
proc onExit(sensor: var Sensor, gameState: var GameState) = discard

proc update(sensor: var Sensor, gameState: var GameState, dt: float32, active: bool) =
  if active:
    var
      props: seq[GlyphProperties]
      nameProp = GlyphProperties(foreground: parseHtmlColor"Orange")
      yellow = GlyphProperties(foreground: parseHtmlColor"Yellow")
      red = GlyphProperties(foreground: parseHtmlColor"red")

    var entries: seq[Entry]
    let player = gameState.world.player
    for entry in gameState.world.nonPlayerEntities:
      if entries.len > 100:
        break
      let
        deltaX = entry.x - player.x
        deltaY = entry.y - player.y
        dist = sqrt(deltaX * deltaX + deltaY * deltaY)
      entries.add Entry(
        name: entry.name,
        distance: dist,
        x: entry.x,
        y: entry.y,
        speed: entry.velocity,
        faction: entry.faction)


    entries = entries.sortedByIt(it.distance)
    for entry in entries.toOpenArray(0, min(entries.high, 10)):
      if entry.faction == Alliance:
        props.add red
      else:
        props.add nameProp
      props.add gameState.buffer.properties
      props.add gameState.buffer.properties
      props.add gameState.buffer.properties
      props.add gameState.buffer.properties
      if entry.faction == Alliance:
        props.add red
      else:
        props.add yellow

    gameState.buffer.printTable(entries.toOpenArray(0, min(entries.high, 10)), entryProperties = props)

proc sensorHandler(gameState: var GameState, input: string) =
  if gameState.hasProgram "Sensor":
    gameState.enterProgram("Sensor")
  else:
    gameState.enterProgram(Sensor().toTrait(Program))

command(
  "sensors",
  "Prints out information of nearby ships and points of interest",
  sensorHandler
)
