{.used.}
import gamestates
import ../screenutils/texttables
import ../data/[spaceentity, worlds]
import std/[algorithm, strutils]
import pkg/truss3D/inputs
import pkg/truss3D

proc formatSpeed(f: float32): string =
  formatFloat(f, ffDecimal, precision = 2)

type
  Sensor = object
    page: int
  Entry = object
    name: string
    faction: Faction
  SensorCommand = object

proc name(sensor: Sensor): string = "Sensor"
proc onExit(sensor: var Sensor, gameState: var GameState) = discard
proc getFlags(_: Sensor): ProgramFlags = {}

proc update(sensor: var Sensor, gameState: var GameState, truss: var Truss, dt: float32, flags: ProgramFlags) =
  if Draw in flags:
    var
      props: seq[GlyphProperties]
      nameProp = GlyphProperties(foreground: parseHtmlColor"Orange")
      yellow = GlyphProperties(foreground: parseHtmlColor"Yellow")
      red = GlyphProperties(foreground: parseHtmlColor"red")

    var entries: seq[Entry]
    let player = gameState.activeShip
    for entry in gameState.world.allInSensors(player):
      entries.add Entry(
        name: entry.name,
        faction: entry.faction
      )


    if TakeInput in flags:
      if truss.inputs.isDownRepeating(KeyCodeDown):
        inc sensor.page

      if truss.inputs.isDownRepeating(KeyCodeUp):
        dec sensor.page


    let
      entriesPerPage = gamestate.buffer.lineHeight - 3
      pages = entries.len div entriesPerPage

    sensor.page = clamp(sensor.page, 0, pages)
    let currentEntry = sensor.page * entriesPerPage

    for entry in entries.toOpenArray(currentEntry, min(entries.high, currentEntry + entriesPerPage)):
      props.add gameState.buffer.properties
      props.add gameState.buffer.properties


    gameState.buffer.printPaged(entries.toOpenArray(currentEntry, min(entries.high, currentEntry + entriesPerPage)))

proc handler(_: SensorCommand, gameState: var GameState, input: string) =
  if gameState.hasProgram "Sensor":
    gameState.enterProgram("Sensor")
  else:
    gameState.enterProgram(Sensor().toTrait(Program))

proc name(_: SensorCommand): string = "sensors"
proc help(_: SensorCommand): string = "Prints out information of nearby ships and points of interest"
proc manual(_: SensorCommand): string = ""
proc suggest(_: SensorCommand, gameState: GameState, input: string, ind: var int): string = discard

storeCommand SensorCommand().toTrait(CommandImpl)
