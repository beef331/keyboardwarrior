{.used.}
import gamestates
import ../data/[spaceentity, inventories, worlds, insensitivestrings]
import ../screenutils/[texttables, progressbars]
import std/[strutils, strformat, tables]

type
  CombatStatusEntry = object
    name: string
    health: int
    status: string
  CombatStatus = object

proc status(sys: inventories.System): string = discard

proc printStatus(gameState: var GameState, combatState: CombatState) =
  gameState.buffer.put(gameState.world.getEntity(combatState.entity).name)
  gameState.buffer.newLine()
  var data: seq[CombatStatusEntry]
  gameState.buffer.put("Hull: ")
  gameState.buffer.put($combatState.hull)
  gameState.buffer.progressbar(combatState.hull / combatState.maxHull, 10, gradient = [(GlyphProperties(foreground: parseHtmlColor"red"), 0f), (GlyphProperties(foreground: parseHtmlColor"lime"), 1f)])
  gameState.buffer.newLine()

  gameState.buffer.put("=".repeat(gamestate.buffer.lineWidth))
  gameState.buffer.newLine()

  for name, system in combatState.systems.pairs:
    gameState.buffer.put(name & ": " & $system.realSystem.currentHealth)
    gameState.buffer.progressbar(system.realSystem.currentHealth / system.realSystem.maxHealth, 10, gradient = [(GlyphProperties(foreground: parseHtmlColor"red"), 0f), (GlyphProperties(foreground: parseHtmlColor"lime"), 1f)])
    gameState.buffer.newLine()




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
proc suggest(_: CombatStatus, gameState: GameState, input: string, ind: var int): string = discard

storeCommand CombatStatus().toTrait(CommandImpl), {InCombat}
