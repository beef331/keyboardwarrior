{.used.}
import gamestates
import std/[strscans, setutils, strbasics, strformat, strutils, tables]
import "$projectdir"/data/[spaceentity, insensitivestrings, worlds]
import "$projectdir"/utils/todoer

type
  Combat = object
  Fire = object
  Energy = object

proc handler(_: Combat, gameState: var GameState, input: string) =
  if (var (success, target) = input.scanTuple("$s$+"); success):
    target.strip()
    if gameState.hasEntity(target, {Ship, Station}):
      gameState.world.enterCombat(gameState.activeShip, target)
    else:
      gameState.writeError(fmt"No ship or station named: '{target}' found.")
  else:
    gameState.writeError("Expected: 'combat target'.")

proc suggest(_: Combat, gameState: GameState, input: string, ind: var int): string =
  case input.suggestIndex()
  of 0, 1:
    iterator allShips(gameState: GameState): string =
      for ent in gameState.world.allInSensors(gameState.activeShip):
        if ent.kind in {Ship, Station}:
          yield ent.name
    suggestNext(gameState.allShips(), input, ind)
  else:
    ""

proc name(_: Combat): string = "combat"
proc help(_: Combat): string = "Start combat with a ship or station"
proc manual(_: Combat): string = ""

storeCommand Combat().toTrait(CommandImpl), {InWorld}

proc printCurrentEnergy(gameState: var GameState) =
  let
    combat = gameState.world.findCombatWith(gameState.activeShip)
    combatState = combat.entityToCombat[gameState.activeShip]

  const color = [
    Weapons: parseHtmlColor"orange",
    Shields: parseHtmlColor"blue",
    Logistics: parseHtmlColor"green",
    Engines: parseHtmlColor"yellow",
  ]


  gameState.buffer.put "Unallocated " & "■".repeat(combatState.energyCount)
  gameState.buffer.put "□".repeat(combatState.maxEnergyCount - combatState.energyCount), GlyphProperties(foreground: parseHtmlColor"grey")
  gameState.buffer.newline()

  for name, energy in combatState.energyDistribution:
    gameState.buffer.put $name & " " & "■".repeat(energy), GlyphProperties(foreground: color[name])
    gameState.buffer.put "□".repeat(combatState.maxEnergyCount - energy),  GlyphProperties(foreground: color[name])
    gameState.buffer.newline()


proc handler(_: Energy, gameState: var GameState, input: string) =
  var errored = false
  if input.isEmptyOrWhitespace():
    discard

  elif (var (success, energy, amount) = input.scanTuple("$s$+ $i"); success):
    try:
      let
        power = insensitiveParseEnum[EnergyPoints](energy)
        combat = gameState.world.findCombatWith(gameState.activeShip)
        combatState = combat.entityToCombat[gameState.activeShip]
        maxEnergyForSystem = combatState.energyDistribution[power] + combatState.energyCount

      if amount < 0:
        errored = true
        gameState.writeError("Cannot set the power to below zero.")
      elif amount > maxEnergyForSystem:
        errored = true
        gameState.writeError(fmt"Cannot give the system more than {maxEnergyForSystem} with currrent energy distribution.")
      else:
        let toAdd = amount - combatState.energyDistribution[power]
        combatState.energyDistribution[power] += toAdd
        combatState.energyCount -= toAdd

    except CatchableError:
      errored = true
      gameState.writeError("Expected {Shield | Weapon | Logistics | Engine}.")
  else:
    errored = true
    gameState.writeError("Expected: 'energy {Shield | Weapon | Logistic | Engine} powerlevel'.")

  if not errored:
    gameState.printCurrentEnergy()


proc suggest(_: Energy, gameState: GameState, input: string, ind: var int): string =
  case input.suggestIndex()
  of 0, 1:
    iterator powerableSystems(_: GameState): string =
      for state in EnergyPoints:
        yield $state
    suggestNext(gameState.powerableSystems(), input, ind)
  else:
    ""

proc name(_: Energy): string = "energy"
proc help(_: Energy): string = "Adjust energy level of systems"
proc manual(_: Energy): string = ""

storeCommand Energy().toTrait(CommandImpl), {InCombat}
