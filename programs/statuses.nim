{.used.}
import gamestates
import ../data/[spaceentity, inventories, worlds, insensitivestrings]
import ../screenutils/[texttables, styledtexts]
import std/[strutils, strformat, tables]


proc healthFormat(data: tuple[current, max: int]): StyledText =
  let progress =
    if data.max <= 0:
      0f
    else:
      data.current / data.max

  styledText(
    $data.current & "/" & $data.max,
    GlyphProperties(
      foreground: lerp(parseHtmlColor"red", parseHtmlColor"lime", progress),
      shakeSpeed: 1f,
      shakeStrength: 0.25f * (1 - progress)
    )
  )

type
  CombatStatusEntry = object
    name: string
    health {.tableStringify: healthFormat.}: tuple[current, max: int]

  CombatStatus = object

proc status(sys: inventories.System): string = discard

proc printStatus(gameState: var GameState, combatState: CombatState) =
  var
    data: seq[CombatStatusEntry]
    properties: seq[GlyphProperties]

  for sys in combatState.systems.values:
    data.add CombatStatusEntry(name: sys.realSystem.name.string, health: (sys.realSystem.currentHealth, sys.realSystem.maxHealth))


  gameState.buffer.printTable(data)






proc handler(_: CombatStatus, gameState: var GameState, input: string) =
  if input.isEmptyOrWhiteSpace():
    gameState.printStatus(gameState.activeCombat.entityToCombat[gameState.activeShip])
  else:
    let
      name = input.strip()
      combat = gameState.activeCombat

    var foundTheTarget = false

    for ship in combat.entityToCombat.keys:
      if gameState.getEntity(ship).name == name:
        gameState.printStatus(combat.entityToCombat[ship])
        foundTheTarget = true
        break

    if not foundTheTarget:
      gameState.writeError(fmt"No entity named: {name}")



proc name(_: CombatStatus): string = "status"
proc help(_: CombatStatus): string = "Prints out a cursory status of the ship"
proc manual(_: CombatStatus): string = ""
proc suggest(_: CombatStatus, gameState: GameState, input: string, ind: var int): string =
  case input.suggestIndex()
  of 0, 1:
    iterator entitiesInCombat(gameState: GameState): string =
      let combat = gameState.activeCombat
      for entity in combat.entityToCombat.keys:
        yield string gameState.world.getEntity(entity).name

    suggestNext(gameState.entitiesInCombat(), input, ind)

  else:
    ""

storeCommand CombatStatus().toTrait(CommandImpl), {InCombat}
