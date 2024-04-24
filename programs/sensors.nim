import gamestates
import ../screenutils/texttables
import ../data/spaceentity
import std/[algorithm, strutils]

proc formatDistance(f: float32): string =
  formatFloat(f, precision = 6)
proc formatSpeed(f: float32): string =
  formatFloat(f, precision = 3)
proc formatPos(f: float32): string =
  formatFloat(f, precision = 5)
type
  Sensor = object
  Entry = object
    name: string
    x {.tableStringify(formatSpeed).}: float32
    y {.tableStringify(formatSpeed).}: float32
    distance {.tableStringify(formatDistance).}: float32
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
    for entry in gameState.world.nonPlayerEntities:
      if entries.len > 10:
        break
      let dist = sqrt(entry.x * entry.x + entry.y * entry.y)
      entries.add Entry(
        name: entry.name,
        distance: dist,
        x: entry.x,
        y: entry.y,
        speed: entry.velocity,
        faction: entry.faction)


    entries = entries.sortedByIt(it.distance)
    for entry in entries:
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
