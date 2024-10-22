import spaceentity, insensitivestrings, inventories
import "$projectdir"/screenutils/screenrenderer
import std/[options, tables, setutils, random, sysrand, hashes, deques]

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

  EnergyPoints = enum
    Weapons
    Shields
    Logistics
    Engines

  CombatState = object
    hull*: int
    maxHull: int
    shield*: int
    maxShield*: int
    energyDistribution: array[EnergyPoints, int]
    energyCount: int
    entity: ControlledEntity


  Combat = object # TODO: Move to own module?
    ships: Table[int, CombatState] # Ships engaged in this combat
    turnOrder: Deque[int] # always `popFirst` uses deque to add dynamically



  World* = object
    idCounter: LocationId
    locations: seq[Location] # 0th location is always 0, 0
    nameToLocation: Table[InsensitiveString, LocationId] # So we can O(1) find from user input, consider `info sol` which provides known information about `sol` (stations, scanned asterorids, phenmonenon)
    playerName: string # GUID no other ship can use this
    seed: int # Start seed to allow reloading state from chunks
    randState*: Rand
    inventoryItems: Table[InsensitiveString, InventoryEntry] # We do not want to remake InventoryItems so they're the same off reference

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
      shipData:
        ShipData(
          glyphProperties: GlyphProperties(foreground: parseHtmlColor("white"), background: parseHtmlColor("black")),
          systems: @[
            System(name: insStr"Sensor Array", kind: Sensor, sensorRange: 50, powerUsage: 100),
            System(name: insStr"Hacker", kind: Hacker, hackSpeed: 1, hackRange: 100, powerUsage: 25),
            System(name: insStr"Warp Core", kind: Generator, powerUsage: 300),
            System(name: insStr"WBay1", kind: WeaponBay, interactionDelay: 0.7f, currentAmmo: 100),
            System(name: insStr"Drill1", kind: ToolBay, interactionDelay: 1f, toolRange: 10),
            System(name: insStr"BasicStorage", kind: Inventory, maxWeight: 1000),
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
        SpaceEntity(name: startLocation.nextName("testerino"), kind: Station)
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

func tryJoinCombat(world: var World, combat: var Combat, initiator: ControlledEntity, target: InsensitiveString): bool =
  ## Joins an existent combat if target is in combat, returns whether it joined
  for ent in combat.ships.values:
    if world.getEntity(ent.entity).name == target:
      combat.ships[combat.ships.len] = CombatState(entity: initiator)
      combat.turnOrder.addFirst(combat.ships.len - 1) # The initiator takes the next move 'always
      return true

func startCombat(state: sink CombatState, entity: SpaceEntity): CombatState =
  result = move state
  result.hull  = entity.currentHull
  result.maxHull = entity.maxHull
  #[
  for system in entity.systemsOf({Shield}):
    result.maxShield += system.maxShield

  for system in entity.systemsOf({WeaponBay}):
    discard
  ]#


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
      ships: {
        0: CombatState(entity: initiator).startCombat(world.getEntity(initiator)),
        1: CombatState(entity: theTarget).startCombat(world.getEntity(theTarget))
      }.toTable(),
      turnOrder: [0, 1].toDeque()
    )


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
