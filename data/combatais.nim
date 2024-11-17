import worlds
import std/[tables]


type
  CombatStance = enum
    Defensive
    Neutral
    Aggressive


proc calculateStance(combat: Combat, ourState: CombatState): CombatStance =
  for entity, state in combat.entityToCombat.pairs:
    discard
