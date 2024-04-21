import gamestates
import ../screenutils/texttables
import std/[algorithm, strutils]

proc formatDistance(f: float32): string =
  formatFloat(f, precision = 4)

type
  Sensor = object
  Entry = object
    name: string
    distance {.tableStringify(formatDistance).}: float32
    speed: float32
    faction: string

var entries: seq[Entry] = @[
  Entry(name: "Orion", distance: 500, speed: 5, faction: "Alliance"),
  Entry(name: "Prometheus", distance: 600, speed: 20, faction: "Incarnate"),
  Entry(name: "Sisyphus", distance: 10000, speed: 100, faction: "Wanderers"),
  Entry(name: "Icarus", distance: 13000, speed: 95, faction: "Wanderers")
]

proc name(sensor: Sensor): string = "Sensor"
proc onExit(sensor: var Sensor, gameState: var GameState) = discard

proc update(sensor: var Sensor, gameState: var GameState, dt: float32, active: bool) =
  var
    props: seq[GlyphProperties]
    nameProp = GlyphProperties(foreground: parseHtmlColor"Orange")
    yellow = GlyphProperties(foreground: parseHtmlColor"Yellow")
    red = GlyphProperties(foreground: parseHtmlColor"red")
  for entry in entries.mitems:
    entry.distance -= entry.speed * dt
    if active:
      if entry.faction == "Alliance":
        props.add red
      else:
        props.add nameProp
      props.add gameState.buffer.properties
      props.add gameState.buffer.properties
      if entry.faction == "Alliance":
        props.add red
      else:
        props.add yellow

  if active:
    entries = entries.sortedByIt(it.distance)
    gameState.buffer.printTable(entries, entryProperties = props)

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
