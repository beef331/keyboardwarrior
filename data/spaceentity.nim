import std/[tables, random, hashes, sysrand, math]
import quadtrees

type
  InventoryEntry = object
    name: string
    count: int
    cost: int
    weight: int

  Compartment = object
    inventory: seq[InventoryEntry]
    maxLoad: int

  EntityKind = enum
    Asteroid
    Planet
    Star
    Ship
    Station

  Faction* = enum
    Universe
    Netural
    Alliance
    Grefeni
    Kulvan
    Jiborn
    #Custom = 16

  SpaceEntity = object
    name*: string
    faction*: Faction
    node: int
    x*, y*: float
    velocity*: float
    heading: float
    kind: EntityKind
    compartments: seq[Compartment]

  Chunk = object
    entities: QuadTree[SpaceEntity]
    nameToEntityInd: Table[string, QuadTreeIndex]
    nameCount: CountTable[string]

  World* = object
    player: QuadTreeIndex
    playerName: string # GUID no other ship can use this
    seed: int # Start seed to allow reloading state from chunks
    randState: Rand
    activeChunks: seq[Chunk] # Load N number of chunks around player



proc isReady*(world: World): bool = world.playerName.len != 0

proc init*(world: var World, playerName, seed: string) =
  world.playerName = playerName
  if seed.len > 0:
    world.seed = int hash(seed)
  else:
    var val: array[8, byte]
    assert urandom(val)
    copyMem(world.seed.addr, val.addr, sizeof(int))

  world.randState = initRand(world.seed)
  var qt = QuadTree[SpaceEntity].init(1000, 1000)
  world.player = qt.add SpaceEntity(name: playerName, x: 500, y: 500)
  world.activeChunks.add Chunk(entities: qt, nameToEntityInd: {playerName: world.player}.toTable())

  const entityNames = ["Freighter", "Asteroid", "Carrier", "Hauler", "Unknown"]

  for _ in 0..100000:
    let
      selectedName = world.randState.sample(entityNames)
      name = selectedName & $world.activeChunks[0].nameCount.getOrDefault(selectedName)
      x = world.randState.rand(100d..900d)
      y =  world.randState.rand(100d..900d)
      vel =  world.randState.rand(1d..10d)
      faction = world.randState.rand(Faction)
      heading = world.randState.rand(0d..Tau)

    world.activeChunks[0].nameToEntityInd[name] = world.activeChunks[0].entities.add SpaceEntity(
      name: name,
      x: x,
      y: y,
      velocity: vel,
      faction: faction,
      heading: heading
      )
    inc world.activeChunks[0].nameCount, selectedName

proc update*(world: var World, dt: float32) =
  for entity in world.activeChunks[0].entities.mitems:
    let
      xOffset = cos(entity.heading)
      yOffset = sin(entity.heading)
    entity.x += dt * entity.velocity * xOffset
    entity.y += dt * entity.velocity * yOffset

  for toMove in world.activeChunks[0].entities.reposition():
    discard toMove # TODO: Move this to the next chunk

iterator nonPlayerEntities*(world: World): lent SpaceEntity =
  for i, ent in world.activeChunks[0].entities.inRangePairs(450, 450, 100, 100):
    if i != world.player:
      yield ent

proc player*(world: World): lent SpaceEntity =
  world.activeChunks[0].entities[world.player]
