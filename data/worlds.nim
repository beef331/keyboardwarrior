import spaceentity, insensitivestrings, inventories, locations, combatstates, combatais
import "$projectdir"/screenutils/screenrenderer
import std/[options, tables, setutils, random, sysrand, hashes, deques, decls]

type
  World* = object
    idCounter: LocationId
    locations: seq[Location] # 0th location is always 0, 0
    nameToLocation: Table[InsensitiveString, LocationId] # So we can O(1) find from user input, consider `info sol` which provides known information about `sol` (stations, scanned asterorids, phenmonenon)
    playerName: string # GUID no other ship can use this
    seed: int # Start seed to allow reloading state from chunks
    randState*: Rand
    inventoryItems: Table[InsensitiveString, InventoryEntry] # We do not want to remake InventoryItems so they're the same off reference


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
  let hull = System(name: insStr"Hull", kind: Hull, currentHealth: 20, maxHealth: 20)
  startLocation.add:
    SpaceEntity(
      kind: Ship,
      name: playerName,
      x: 500,
      hull: hull,
      shipData:
        ShipData(
          glyphProperties: GlyphProperties(foreground: parseHtmlColor("white"), background: parseHtmlColor("black")),
          systems: @[
            hull,
            System(name: insStr"Sensor-Array", kind: Sensor, sensorRange: 50),
            System(name: insStr"Hacker", kind: Hacker, hackSpeed: 1, hackRange: 100),
            System(name: insStr"Warp-Core", kind: Generator, maxHealth: 10, currentHealth: 10, powerGeneration: 15),
            System(name: insStr"Laser-Turret", kind: WeaponBay, flags: {Targetable, TargetOther}, activateCost: 2, damageDealt: [Fire: 3, 0, 0, 0]),
            System(name: insStr"Gauss-Cannon", kind: WeaponBay, flags: {Targetable, TargetOther}, activateCost: 2, damageDealt: [Fire: 4, 0, 0, 0], chargeTurns: 2, chargeEnergyCost: 1),
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
        let hull = System(name: insStr"Hull", kind: Hull, currentHealth: 20, maxHealth: 20)
        SpaceEntity(
          name: startLocation.nextName("testerino"),
          kind: Ship,
          hull: hull,
          shipData:
            ShipData(
              glyphProperties: GlyphProperties(foreground: parseHtmlColor("white"), background: parseHtmlColor("black")),
              systems: @[
                System(name: insStr"Hull", kind: Hull, currentHealth: 20, maxHealth: 20),
                System(name: insStr"Sensor-Array", kind: Sensor, sensorRange: 50),
                System(name: insStr"Hacker", kind: Hacker, hackSpeed: 1, hackRange: 100),
                System(name: insStr"Warp-Core", kind: Generator, maxHealth: 10, currentHealth: 10, powerGeneration: 15),
                System(name: insStr"Gauss-Cannon", kind: WeaponBay, flags: {Targetable}, activateCost: 0, chargeEnergyCost: 2, chargeTurns: 2),
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

proc combatHasEntityNamed*(world: World, combat: Combat, name: InsensitiveString, target: var CombatState): bool =
  for entity, state in combat.entityToCombat.pairs:
    if world.getEntity(entity).name == name:
      target = state
      return true

proc delete[T](s: var seq[T], inds: seq[int]) =
  for i in countDown(inds.high, 0):
    s.delete(inds[i])


proc endTurn*(combat: Combat, world: World) =
  let
    ent = combat.turnOrder.popFirst()
    theState = combat.entityToCombat[ent]

  var toRemove: seq[int]
  for i, action in theState.actions.pairs:
    case action.kind
    of Fire:
      toRemove.add i
      combat.entityToCombat[action.system.target].damages.add DamageEvent(
        damages: action.system.realSystem.damageDealt,
        target: action.system.target,
        targetSystem: action.system.targetSystem
      )
      action.system.chargeAmount = 0


    of Charge:
      inc action.system.chargeAmount
      if action.system.chargeState() == FullyCharged:
        toRemove.add i

  theState.actions.delete(toRemove)


  toRemove.setLen(0)

  for state in combat.entityToCombat.values:
    for i, damage in state.damages.mpairs:
      if damage.handle(combat, state):
        toRemove.add i

    state.damages.delete(toRemove)
    toRemove.setLen(0)

  combat.turnOrder.addLast(ent)

  while combat.turnOrder.peekFirst() != ent:
    combat.turnOrder.addLast(combat.turnOrder.popFirst())
