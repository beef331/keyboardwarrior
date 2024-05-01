import gamestates
import ../data/spaceentity
import ../screenutils/texttables

proc powerFormat(i: int): string = $i & "kw"

type StatusEntry = object
  name: string
  powered: bool
  powerConsumption {.tableStringify(powerFormat).}: int
  status: string

proc statusHandler(gameState: var GameState, input: string) =
  var
    entries: seq[StatusEntry]
    props: seq[GlyphProperties]
  for system in gameState.activeShipEntity.systems:
    entries.add StatusEntry(
      name: system.name,
      powered: Powered in system.flags,
      powerConsumption:(
        if system.kind == Generator:
          system.powerUsage
        else:
          -system.powerUsage),
      status:(
        if Jammed in system.flags:
          "Jammed"
        else:
          ""),
      )

    let
      powerColour =
        if entries[^1].powered:
          GlyphProperties(foreGround: parseHtmlColor"lime")
        else:
          GlyphProperties(foreGround: parseHtmlColor"red")
      powerConsumption =
        if entries[^1].powerConsumption > 0:
          GlyphProperties(foreGround: parseHtmlColor"lime")
        else:
          GlyphProperties(foreGround: parseHtmlColor"red")


    props.add [
      gameState.buffer.properties,
      powerColour,
      powerConsumption,
      gameState.buffer.properties
    ]

  gameState.buffer.printTable(
    entries,
    entryProperties = props
  )



command(
  "status",
  "Prints out a cursory status of the ship",
  statusHandler
)
