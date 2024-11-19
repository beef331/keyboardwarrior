import worlds, combatstates
import std/[tables, math]


type
  CombatStance = enum
    Defensive
    Neutral
    Aggressive

const
  dangerWeight = [
    Hull: 10f,
    Weapons: 3,
    Shields: 8,
    Logistics: 2,
    Engines: 5,
  ]


proc dangerLevel(system: CombatSystem): float32 =
  let theWeight = dangerWeight[system.kind]
  case system.kind
  of Hull:
    (system.realSystem.currentHealth / system.realSystem.maxHealth) * theWeight
  of Weapons:
    if system.chargeState == NotChargable:
      (system.realSystem.currentHealth > 0).float32 * theWeight * system.realSystem.damageModifier.sum()
    else:
      (system.chargeState == FullyCharged).float32 * theWeight * system.realSystem.damageModifier.sum()
  of Shields:
    (system.realSystem.currentShield / system.realSystem.maxShield) * theWeight
  else:
    0


proc calculateDangerLevel(state: CombatState) =
  var
    combatWeights: array[CombatSystemKind, int]
    combatCounts: array[CombatSystemKind, int]


  for system in state.systems.values:
    discard


proc calculateStance(combat: Combat, ourState: CombatState): CombatStance =
  for entity, state in combat.entityToCombat.pairs:
    discard
