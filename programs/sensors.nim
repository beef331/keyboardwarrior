{.used.}
import gamestates
import ../screenutils/texttables
import ../data/spaceentity
import std/[algorithm, strutils]
import pkg/truss3D/inputs

proc formatSpeed(f: float32): string =
  formatFloat(f, ffDecimal, precision = 2)

type
  Sensor = object
    page: int
  Entry = object
    name: string
    x {.tableStringify(formatSpeed).}: float32
    y {.tableStringify(formatSpeed).}: float32
    distance {.tableStringify(formatSpeed).}: float32
    speed {.tableStringify(formatSpeed).}: float32
    faction: Faction

proc name(sensor: Sensor): string = "Sensor"
proc onExit(sensor: var Sensor, gameState: var GameState) = discard
proc getFlags(_: Sensor): ProgramFlags = {}

proc update(sensor: var Sensor, gameState: var GameState, dt: float32, flags: ProgramFlags) =
  if Draw in flags:
    var
      props: seq[GlyphProperties]
      nameProp = GlyphProperties(foreground: parseHtmlColor"Orange")
      yellow = GlyphProperties(foreground: parseHtmlColor"Yellow")
      red = GlyphProperties(foreground: parseHtmlColor"red")

    var entries: seq[Entry]
    let player = gameState.world.player
    for entry in gameState.world.nonPlayerEntities:
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

    if TakeInput in flags:
      if KeyCodeDown.isDownRepeating():
        inc sensor.page

      if KeyCodeUp.isDownRepeating():
        dec sensor.page


    let
      entriesPerPage = gamestate.buffer.lineHeight - 3
      pages = entries.len div entriesPerPage

    sensor.page = clamp(sensor.page, 0, pages)
    let currentEntry = sensor.page * entriesPerPage

    for entry in entries.toOpenArray(currentEntry, min(entries.high, currentEntry + entriesPerPage)):
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

    gameState.buffer.printPaged(entries.toOpenArray(currentEntry, min(entries.high, currentEntry + entriesPerPage)), entryProperties = props)

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
