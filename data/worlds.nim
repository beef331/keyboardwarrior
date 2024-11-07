import spaceentity, insensitivestrings, inventories
import "$projectdir"/screenutils/screenrenderer
import std/[options, tables, setutils, random, sysrand, hashes, deques, decls]

type
  Location = object
    name: InsensitiveString
    id: LocationId
    x,y: int
    entities: seq[SpaceEntity] # Use a quad tree?
    neighbours: array[10, Option[LocationId]]
    combats: seq[Combat] # If player is not in it, slowly tick it along simulating combat
    nameCount: CountTable[string]

  ControlledEntity* = ref object
    location*: LocationId
    entryId*: int

  CombatSystemKind* = enum
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

  FireError* = enum
    None
    InsufficientlyCharged = $CombatInteractError
    NoTarget = "Has no target"


  ChargeState* = enum
    NotChargable
    NotCharged
    FullyCharged


  CombatSystem = object
    kind*: CombatSystemKind
    realSystem*: System
    flags: set[CombatSystemFlag]
    chargeAmount*: int # amount of turns charged
    targetSystem*: InsensitiveString
    target*: ControlledEntity
    combatState*: CombatState


  ActionEffect = enum
    Interrupt
    Interruptable


  Action = object
    effects: set[ActionEffect]
    damages: DamageDealt
    turnsToImpact: int
    targetSystem: InsensitiveString
    target: ControlledEntity


  CombatState* = ref object
    hull*: int
    maxHull*: int
    shield*: int
    maxShield*: int
    energyUsed*: array[CombatSystemKind, int]
    energyDistribution*: array[CombatSystemKind, int]
    systems*: Table[InsensitiveString, CombatSystem]
    energyCount*: int
    maxEnergyCount*: int
    entity*: ControlledEntity
    actions: seq[Action]


  Combat* = ref object # TODO: Move to own module?
    entityToCombat*: Table[ControlledEntity, CombatState]
    turnOrder*: Deque[ControlledEntity] # always `popFirst` uses deque to add dynamically
    activeEntity*: ControlledEntity

  World* = object
    idCounter: LocationId
    locations: seq[Location] # 0th location is always 0, 0
    nameToLocation: Table[InsensitiveString, LocationId] # So we can O(1) find from user input, consider `info sol` which provides known information about `sol` (stations, scanned asterorids, phenmonenon)
    playerName: string # GUID no other ship can use this
    seed: int # Start seed to allow reloading state from chunks
    randState*: Rand
    inventoryItems: Table[InsensitiveString, InventoryEntry] # We do not want to remake InventoryItems so they're the same off reference

proc `==`*(a, b: LocationId): bool = a.int == b.int

proc `==`*(a, b: ControlledEntity): bool =
  (a.isNil and b.isNil) or (not(a.isNil) and not(b.isNil) and a[] == b[])

proc hash*(ent: ControlledEntity): Hash =
  if ent.isNil:
    hash(0)
  else:
    hash(ent[])

proc nextName(loc: var Location, name: string): string =
  result = name
  let count = loc.nameCount.getOrDefault(name)
  if count != 0:
    result.add $count

  inc loc.nameCount, name

proc nextLocationID(world: var World): LocationId =
  result = world.idCounter
  inc world.idCounter.int

proc add*(location: var Location, ent: sink SpaceEntity) =
  ent.location = location.id
  ent.locationIndex = location.entities.len
  location.entities.add ent

proc isReady*(world: World): bool = world.playerName.len != 0

proc add*(world: var World, item: InventoryEntry): InventoryEntry {.discardable.} =
  world.inventoryItems[item.name] = item
  item

proc getEntry*(world: World, name: InsensitiveString): InventoryEntry =
  world.inventoryItems[name]

proc getItems*(world: World, filter: set[InventoryKind]): seq[InventoryEntry] =
  for value in world.inventoryItems.values:
    if value.kind in filter:
      result.add value

proc makeOres(world: var World) =
  world.add InventoryEntry(
    kind: Ore,
    name: insStr"Iron Ore",
    weight: 10,
    operationResult: [world.add(InventoryEntry(kind: Ingot, weight: 13, name: insStr"Iron Ingot")), nil],
    operationCount: [1, 0]

  )
  world.add InventoryEntry(
    kind: Ore,
    name: insStr"Lithium Ore",
    weight: 2,
    operationResult: [world.add(InventoryEntry(kind: Ingot, weight: 3, name: insStr"Lithium Ingot")), nil],
    operationCount: [1, 0]
  )

  world.add InventoryEntry(
    kind: Ore,
    name: insStr"Aluminium Ore",
    weight: 4,
    operationResult: [world.add(InventoryEntry(kind: Ingot, weight: 5, name: insStr"Aluminium Ingot")), nil],
    operationCount: [1, 0]
  )

  world.add InventoryEntry(
    kind: Ore,
    name: insStr"Lead Ore",
    weight: 12,
    operationResult: [world.add(InventoryEntry(kind: Ingot, weight: 16, name: insStr"Lead Ingot")), nil],
    operationCount: [1, 0]
  )

proc init*(world: var World, playerName, seed: string) =
  world.playerName = playerName
  if seed.len > 0:
    world.seed = int hash(seed)
  else:
    var val: array[8, byte]
    assert urandom(val)
    copyMem(world.seed.addr, val.addr, sizeof(int))
  world.makeOres()
  world.randState = initRand(world.seed)
  var startLocation = Location(id: world.nextLocationID())
  startLocation.add:
    SpaceEntity(
      kind: Ship,
      name: playerName,
      x: 500,
      currentHull: 100,
      maxHull: 100,
      shipData:
        ShipData(
          glyphProperties: GlyphProperties(foreground: parseHtmlColor("white"), background: parseHtmlColor("black")),
          systems: @[
            System(name: insStr"Sensor-Array", kind: Sensor, sensorRange: 50),
            System(name: insStr"Hacker", kind: Hacker, hackSpeed: 1, hackRange: 100),
            System(name: insStr"Warp-Core", kind: Generator, maxHealth: 10, currentHealth: 10, powerGeneration: 15),
            System(name: insStr"Laser-Turret", kind: WeaponBay, flags: {Targetable}, activateCost: 2, damageDealt: [Fire: 3, 0, 0, 0]),
            System(name: insStr"Guass-Cannon", kind: WeaponBay, flags: {Targetable}, activateCost: 2, damageDealt: [Fire: 4, 0, 0, 0], chargeTurns: 2, chargeEnergyCost: 1),
            System(name: insStr"Drill1", kind: ToolBay),
            System(name: insStr"Basic-Storage", kind: Inventory, maxWeight: 1000),
          ]
      )
    )

  let ores = world.getItems({Ore})
  for i in 0..100:
    let entity =
      case world.randState.rand(EntityKind)
      of Asteroid:
        var
          spawnable = {range[0..100](0) .. range[0..100](ores.high)}
          asteroid = SpaceEntity(kind: Asteroid, name: startLocation.nextName("Asteroid"))

        for _ in 0..world.randState.rand(ores.high):
          let ore = world.randState.sample(spawnable)
          spawnable.excl ore
          asteroid.resources.add InventoryItem(entry: ores[int ore], amount: world.randState.rand(100))
        asteroid
      else:
        SpaceEntity(
          name: startLocation.nextName("testerino"),
          kind: Ship,
          currentHull: 100,
          maxHull: 100,
          shipData:
            ShipData(
              glyphProperties: GlyphProperties(foreground: parseHtmlColor("white"), background: parseHtmlColor("black")),
              systems: @[
                System(name: insStr"Sensor-Array", kind: Sensor, sensorRange: 50),
                System(name: insStr"Hacker", kind: Hacker, hackSpeed: 1, hackRange: 100),
                System(name: insStr"Warp-Core", kind: Generator, maxHealth: 10, currentHealth: 10, powerGeneration: 15),
                System(name: insStr"Guass-Cannon", kind: WeaponBay, flags: {Targetable}, activateCost: 0, chargeEnergyCost: 2, chargeTurns: 2),
                System(name: insStr"Basic-Storage", kind: Inventory, maxWeight: 1000),
              ]
          )
        )
    startLocation.add entity


  world.locations.add startLocation

func getEntity*(world: World, entity: ControlledEntity): lent SpaceEntity =
  world.locations[entity.location.int].entities[entity.entryId]

func getEntity*(world: var World, entity: ControlledEntity): var SpaceEntity =
  world.locations[entity.location.int].entities[entity.entryId]

func hasEntity*(world: World, locationId: LocationId, name: string, kind: set[EntityKind] = EntityKind.fullSet): bool =
  for x in world.locations[locationId.int].entities:
    if x.name == InsensitiveString(name):
      return x.kind in kind

func getEntity*(world: World, locationId: LocationId, name: string): lent SpaceEntity =
  for x in world.locations[locationId.int].entities:
    if x.name == InsensitiveString(name):
      return x
  raise newException(ValueError, "Cannot find entity named: " & name)

func getEntity*(world: var World, locationId: LocationId, name: string): var SpaceEntity =
  for x in world.locations[locationId.int].entities.mitems:
    if x.name == InsensitiveString(name):
      return x
  raise newException(ValueError, "Cannot find entity named: " & name)

func getEntityId*(world: World, locationId: LocationId, name: string): int=
  for i, x in world.locations[locationId.int].entities.pairs:
    if x.name == InsensitiveString(name):
      return i
  raise newException(ValueError, "Cannot find entity named: " & name)

func getEntityId*(world: World, locationId: LocationId, name: InsensitiveString): int=
  for i, x in world.locations[locationId.int].entities.pairs:
    if x.name == name:
      return i
  raise newException(ValueError, "Cannot find entity named: " & name)

func entityExists*(world: World, locationId: LocationId, name: string): bool =
  for x in world.locations[locationId.int].entities:
    if x.name == InsensitiveString(name):
      return true

func entityExists*(world: World, locationId: LocationId, name: InsensitiveString): bool =
  for x in world.locations[locationId.int].entities:
    if x.name == name:
      return true

func findCombatWith*(world: World, entity: ControlledEntity): Combat =
  for combat in world.locations[entity.location.int].combats:
    if entity in combat.entityToCombat:
      return combat

  raise newException(ValueError, "No ship in combat")

func tryJoinCombat(world: var World, combat: var Combat, initiator: ControlledEntity, target: InsensitiveString): bool =
  ## Joins an existent combat if target is in combat, returns whether it joined
  for ent in combat.entityToCombat.keys:
    if world.getEntity(ent).name == target:
      combat.entityToCombat[initiator] = CombatState(entity: initiator)
      combat.turnOrder.addFirst(initiator) # The initiator takes the next move 'always
      return true

func startCombat(state: sink CombatState, entity: SpaceEntity): CombatState =
  result = move state
  result.hull  = entity.currentHull
  result.maxHull = entity.maxHull
  result.maxEnergyCount = entity.generatedPower()
  result.energyCount = result.maxEnergyCount

  for system in entity.systemsOf({Shield}):
    result.maxShield += system.maxShield


  for system in entity.systemsOf(NotSystem.default()):
    result.systems[system.name] = CombatSystem(
      kind: Weapons,
      realSystem: system,
      combatState: result,
    )


func enterCombat*(world: var World, initiator: ControlledEntity, target: string) =
  var joined = false
  for combat in world.locations[initiator.location.int].combats.mitems:
    if (joined = world.tryJoinCombat(combat, initiator, target.InsensitiveString); joined):
      break

  if not joined:
    let theTarget = ControlledEntity(location: initiator.location)
    for i, x in world.locations[initiator.location.int].entities:
      if x.name == target.InsensitiveString:
        theTarget.entryId = i
        break

    assert theTarget != nil

    world.locations[initiator.location.int].combats.add Combat(
      entityToCombat: {
        initiator: CombatState(entity: initiator).startCombat(world.getEntity(initiator)),
        theTarget: CombatState(entity: theTarget).startCombat(world.getEntity(theTarget))
      }.toTable(),
      turnOrder: [initiator, theTarget].toDeque(),
      activeEntity: initiator
    )
    world.locations[theTarget.location.int].entities[theTarget.entryId].state = InCombat

  world.locations[initiator.location.int].entities[initiator.entryId].state = InCombat

iterator allInSensors*(world: World, entity: ControlledEntity): lent SpaceEntity =
  for i, x in world.locations[int entity.location].entities:
    if i != entity.entryId:
      yield x

proc update*(world: var World, dt: float32) =
  discard


iterator entitiesIn*(world: World, id: LocationId, filter: set[EntityKind] = EntityKind.fullSet): lent SpaceEntity =
  for ent in world.locations[id.int].entities:
    if ent.kind in filter:
      yield ent

iterator entitiesIn*(world: var World, id: LocationId, filter: set[EntityKind] = EntityKind.fullSet): var SpaceEntity =
  for ent in world.locations[id.int].entities.mitems:
    if ent.kind in filter:
      yield ent


proc unusedPower(state: CombatState, kind: CombatSystemKind): int =
  state.energyDistribution[kind] - state.energyUsed[kind]

proc hasSystemNamed*(combat: CombatState, name: InsensitiveString): bool = name in combat.systems

proc combatHasEntityNamed*(world: World, combat: Combat, name: InsensitiveString, target: var CombatState): bool =
  for entity, state in combat.entityToCombat.pairs:
    if world.getEntity(entity).name == name:
      target = state
      return true

proc powerOn*(state: CombatState, system: InsensitiveString): CombatInteractError =
  let sys {.byaddr.} = state.systems[system]
  if state.unusedPower(sys.kind) < sys.realSystem.chargeEnergyCost:
    NotEnoughPower
  elif Active in sys.flags:
    AlreadyPowered
  else:
    sys.flags.incl Active
    state.energyUsed[sys.kind] += sys.realSystem.chargeEnergyCost
    None

proc powerOff*(state: CombatState, system: InsensitiveString): CombatInteractError =
  let sys {.byaddr.} = state.systems[system]
  if Active in sys.flags:
    state.energyUsed[sys.kind] -= sys.realSystem.chargeEnergyCost
    None
  else:
    AlreadyUnpowered

proc targetableCount*(state: CombatState): int =
  for system in state.systems.values:
    if Targetable in system.realSystem.flags:
      inc result

proc turnsTillCharged*(system: CombatSystem): int =
  system.realSystem.chargeTurns - system.chargeAmount


proc fireState*(system: CombatSystem): FireError =
  if system.target == nil or system.targetSystem == InsensitiveString"":
    NoTarget
  elif system.turnsTillCharged() != 0:
    InsufficientlyCharged
  else:
    None

proc chargeState*(combatSystem: CombatSystem): ChargeState =
  if combatSystem.realSystem.chargeTurns == 0:
    NotChargable
  elif combatSystem.turnsTillCharged() != 0:
    NotCharged
  else:
    FullyCharged


proc fire*(state: CombatState, system: InsensitiveString): CombatInteractError =
  let sys {.byaddr.} = state.systems[system]
  if sys.turnsTillCharged > 0:
    InsufficientlyCharged
  elif state.unusedPower(sys.kind) < sys.realSystem.activateCost:
    NotEnoughPower
  else:
    sys.flags.incl CombatSystemFlag.Fire
    state.energyUsed[sys.kind] += sys.realSystem.activateCost
    None

proc holdfire*(state: CombatState, system: InsensitiveString): CombatInteractError =
  let sys {.byaddr.} = state.systems[system]
  if Fire in sys.flags:
    state.energyUsed[sys.kind] -= sys.realSystem.activateCost
  sys.flags.excl CombatSystemFlag.Fire
  None


proc handle(action: Action, combat: Combat, combatState: CombatState): bool =
  # returns true if it should be removed from the list
  if action.turnsToImpact <= 0:
    let system = combat.entityToCombat[action.target].systems[action.targetSystem].realSystem
    for kind, damage in action.damages:
      system.currentHealth -= int(action.damages[kind].float32 * system.damageModifier[kind])

    if Interrupt in action.effects:
      combatState.systems[action.targetSystem].flags.excl Active
    true
  else:
    false


proc endTurn*(combat: Combat) =
  let nextState = combat.entityToCombat[combat.turnOrder.peekFirst()]
  for system in nextState.systems.mvalues:
    if Active in system.flags:
      inc system.chargeAmount
      if system.turnsTillCharged() == 0:
        system.flags.excl Active
        system.flags.incl Charged
        nextState.energyUsed[system.kind] -= system.realSystem.chargeEnergyCost

    if Fire in system.flags:
      system.combatState.actions.add Action(
        damages: system.realSystem.damageDealt,
        target: system.target,
        targetSystem: system.targetSystem
      )
      nextState.energyUsed[system.kind] -= system.realSystem.activateCost


  for state in combat.entityToCombat.values:
    var toRemove: seq[int]
    for i, action in state.actions.mpairs:
      dec action.turnsToImpact
      if action.handle(combat, state):
        toRemove.add i
    for i in toRemove:
      state.actions.delete(i)

  combat.turnOrder.addLast(combat.activeEntity)
  combat.activeEntity = combat.turnOrder.popFirst()
