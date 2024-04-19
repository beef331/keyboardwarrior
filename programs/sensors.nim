import gamestates
import ../texttables
import std/algorithm

type Sensor = object

var entries: seq[tuple[name: string, distance, speed: float32, faction: string]] = @[
  ("Orion", 500, 5, "Alliance"),
  ("Prometheus", 600, 20, "Incarnate"),
  ("Sisyphus", 10000, 100.0, "Wanderers"),
  ("Icarus", 13000, 95, "Wanderers")
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
    gameState.buffer.printTable(entries, entryProperties = props, formatProperties = TableFormatProps(floatSigDigs: 4))

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
