{.used.}
import gamestates
import ../data/[spaceentity, inventories]
import ../screenutils/texttables

proc powerFormat(i: int): string = $i & "kw"

type
  StatusEntry = object
    name: string
    powered: bool
    status: string
  StatusCommand = object

proc status(sys: inventories.System): string =
  case sys.kind
  of WeaponBay:
    if Jammed in sys.flags:
      "Jammed"
    elif Toggled in sys.flags:
      "Firing"
    else:
      ""
  else:
    ""

proc handler(_: StatusCommand, gameState: var GameState, input: string) =
  var
    entries: seq[StatusEntry]
    props: seq[GlyphProperties]
  for system in gameState.activeShipEntity.shipData.systems:
    entries.add StatusEntry(
      name: system.name,
      powered: Powered in system.flags,
      status: system.status,
      )

    let
      powerColour =
        if entries[^1].powered:
          GlyphProperties(foreGround: parseHtmlColor"lime")
        else:
          GlyphProperties(foreGround: parseHtmlColor"red")


    props.add [
      gameState.buffer.properties,
      powerColour,
      gameState.buffer.properties
    ]

  gameState.buffer.printTable(
    entries,
    entryProperties = props
  )


proc name(_: StatusCommand): string = "status"
proc help(_: StatusCommand): string = "Prints out a cursory status of the ship"
proc manual(_: StatusCommand): string = ""
proc suggest(_: StatusCommand, gameState: GameState, input: string, ind: var int): string = discard

storeCommand StatusCommand().toTrait(CommandImpl)
