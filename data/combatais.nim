import worlds
import std/[tables]


type
  CombatStance = enum
    Defensive
    Neutral
    Aggressive

proc calculateDangerLevel(state: CombatState): int =
  var
    combatWeights: array[CombatSystemKind, float]
    combatCounts: array[CombatSystemKind, int]

  for system in state.systems:
    case system.kind
    of Weapons:
      discard
    of Shields:
      discard
    of Generator:
      discard


proc calculateStance(combat: Combat, ourState: CombatState): CombatStance =
  for entity, state in combat.entityToCombat.pairs:
    discard
