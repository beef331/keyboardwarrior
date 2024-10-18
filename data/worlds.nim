import spaceentity, insensitivestrings, inventories
import "$projectdir"/screenutils/screenrenderer
import std/[options, tables, setutils, random, sysrand, hashes]

type
  Location = object
    name: InsensitiveString
    id: LocationId
    x,y: int
    entities: seq[SpaceEntity] # Use a quad tree?
    neighbours: array[10, Option[LocationId]]

  ControlledEntity* = ref object
    location*: LocationId
    entryId*: int

  World* = object
    idCounter: LocationId
    locations: seq[Location] # 0th location is always 0, 0
    nameToLocation: Table[InsensitiveString, LocationId] # So we can O(1) find from user input, consider `pathto kronos` which finds the shortest path through non hostile space
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
          asteroid = SpaceEntity(kind: Asteroid, name: "Asteroid")

        for _ in 0..world.randState.rand(ores.high):
          let ore = world.randState.sample(spawnable)
          spawnable.excl ore
          asteroid.resources.add InventoryItem(entry: ores[int ore], amount: world.randState.rand(100))
        asteroid
      else:
        SpaceEntity(name: "testerino")
    startLocation.add entity


  world.locations.add startLocation

func getEntity*(world: World, entity: ControlledEntity): lent SpaceEntity =
  world.locations[entity.location.int].entities[entity.entryId]

func getEntity*(world: var World, entity: ControlledEntity): var SpaceEntity =
  world.locations[entity.location.int].entities[entity.entryId]

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
