import inventories, insensitivestrings, spaceentity
import std/[tables, deques]


type
  CombatSystemKind* = enum
    Hull
    Weapons
    Shields
    Logistics
    Engines

  CombatSystemFlag* = enum
    Active
    Charged
    Fire # Do we fire at end of this turn


  CombatInteractError* = enum
    None
    AlreadyPowered = "The system is already powered."
    AlreadyUnpowered = "The system is already off."
    NotEnoughPower = "There is not enough power allocated for the system."
    InsufficientlyCharged = "Lacking charge need to wait $# turns."
    AlreadyFiring = "Already firing the system $#"

  FireError* = enum
    None
    InsufficientlyCharged = $CombatInteractError.InsufficientlyCharged
    NoTarget = "Has no target"


  ChargeState* = enum
    NotChargable
    NotCharged
    FullyCharged


  CombatSystem* = ref object
    kind*: CombatSystemKind
    realSystem*: System
    flags: set[CombatSystemFlag]
    chargeAmount*: int # amount of turns charged
    targetSystem*: InsensitiveString
    target*: ControlledEntity
    combatState*: CombatState


  DamageEffect* = enum
    Interrupt
    Interruptable


  DamageEvent* = object
    effects*: set[DamageEffect]
    damages*: DamageDealt
    turnsToImpact*: int
    targetSystem*: InsensitiveString
    target*: ControlledEntity

  ActionKind* = enum
    Fire
    Charge

  Action* = object
    kind*: ActionKind
    system*: CombatSystem
    cost*: int


  CombatState* = ref object
    hull*: CombatSystem
    shield*: int
    maxShield*: int
    energyDistribution*: array[CombatSystemKind, int]
    systems*: Table[InsensitiveString, CombatSystem]
    energyCount*: int
    maxEnergyCount*: int
    entity*: ControlledEntity
    damages*: seq[DamageEvent]
    actions*: seq[Action]


  Combat* = ref object # TODO: Move to own module?
    entityToCombat*: Table[ControlledEntity, CombatState]
    turnOrder*: Deque[ControlledEntity] # always `popFirst` uses deque to add dynamically
    activeEntity*: ControlledEntity

proc energyUsed*(combatState: CombatState): array[CombatSystemKind, int] =
  for action in combatState.actions:
    result[action.system.kind] += action.cost

func startCombat*(state: sink CombatState, entity: SpaceEntity): CombatState =
  result = move state
  result.hull  = CombatSystem(
    kind: Hull,
    realSystem: entity.hull,
  )

  result.maxEnergyCount = entity.generatedPower()
  result.energyCount = result.maxEnergyCount

  for system in entity.systemsOf({Shield}):
    result.maxShield += system.maxShield

  result.systems[InsensitiveString "Hull"] = result.hull

  for system in entity.systemsOf({WeaponBay}):
    result.systems[system.name] = CombatSystem(
      kind: Weapons,
      realSystem: system,
      combatState: result,
    )

proc hasSystemNamed*(combat: CombatState, name: InsensitiveString): bool = name in combat.systems

proc unusedPower(state: CombatState, kind: CombatSystemKind): int =
  state.energyDistribution[kind] - state.energyUsed[kind]

proc queuedUp*(state: CombatState, system: CombatSystem, actions: set[ActionKind]): bool =
  for action in state.actions:
    if action.kind in actions and system == action.system:
      return true

proc powerOn*(state: CombatState, system: InsensitiveString): CombatInteractError =
  let system = state.systems[system]
  if state.unusedPower(system.kind) < system.realSystem.chargeEnergyCost:
    NotEnoughPower
  elif state.queuedUp(system, {Charge}):
    AlreadyPowered
  else:
    state.actions.add Action(
        kind: Charge,
        system: system,
        cost: system.realSystem.chargeEnergyCost
      )
    None

proc powerOff*(state: CombatState, system: InsensitiveString): CombatInteractError =
  let system = state.systems[system]
  if Active in system.flags:
    for i in countDown(state.actions.high, 0):
      if state.actions[i].system == system:
        state.actions.delete(i)
    None
  else:
    AlreadyUnpowered

proc numberOfSystemsWithAny*(state: CombatState, flags: set[SystemFlag]): int =
  for system in state.systems.values:
    if flags * system.realSystem.flags != {}:
      inc result

proc turnsTillCharged*(system: CombatSystem): int =
  max(system.realSystem.chargeTurns - system.chargeAmount, 0)


proc fireState*(system: CombatSystem): FireError =
  if system.target == nil or system.targetSystem == InsensitiveString"":
    NoTarget
  elif system.turnsTillCharged() > 0:
    InsufficientlyCharged
  else:
    None

proc chargeState*(combatSystem: CombatSystem): ChargeState =
  if combatSystem.realSystem.chargeTurns == 0:
    NotChargable
  elif combatSystem.turnsTillCharged() > 0:
    NotCharged
  else:
    FullyCharged

proc canTarget*(combatSystem: CombatSystem, this, target: ControlledEntity): bool =
  (TargetSelf in combatSystem.realSystem.flags and this == target) or
  (TargetOther in combatSystem.realSystem.flags and this != target)

proc fire*(state: CombatState, system: InsensitiveString): CombatInteractError =
  let system = state.systems[system]
  if system.turnsTillCharged > 0:
    InsufficientlyCharged
  elif state.unusedPower(system.kind) < system.realSystem.activateCost:
    NotEnoughPower
  elif state.queuedUp(system, {ActionKind.Fire}):
    AlreadyFiring
  else:
    state.actions.add Action(kind: Fire, system: system, cost: system.realSystem.activateCost)
    system.flags.incl Fire
    None

proc holdfire*(state: CombatState, system: InsensitiveString): CombatInteractError =
  let system = state.systems[system]
  for i, action in state.actions:
    if action.kind == Fire and system == action.system:
      state.actions.delete(i)
      break
  None


proc handle*(action: var DamageEvent, combat: Combat, combatState: CombatState): bool =
  # returns true if it should be removed from the list
  dec action.turnsToImpact
  if action.turnsToImpact <= 0:
    let system = combat.entityToCombat[action.target].systems[action.targetSystem].realSystem
    for kind, damage in action.damages:
      system.currentHealth -= int(action.damages[kind].float32 * system.damageModifier[kind])

    if Interrupt in action.effects:
      combatState.systems[action.targetSystem].flags.excl Active
    true
  else:
    false

iterator systemsWithAny*(combatState: CombatState, flags: set[Systemflag]): CombatSystem =
  for sys in combatState.systems.values:
    if flags * sys.realSystem.flags != {}:
      yield sys


iterator targetableEntities*(sys: CombatSystem, combat: Combat, this: ControlledEntity): ControlledEntity =
  for entity in combat.entityToCombat.keys:
    if sys.canTarget(this, entity):
      yield entity
