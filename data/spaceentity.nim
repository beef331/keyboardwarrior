import std/[tables, random, hashes, sysrand]

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

  SpaceEntity = object
    name*, faction*: string
    x*, y*: float
    velocity*: float
    heading: float
    kind: EntityKind
    compartments: seq[Compartment]

  Chunk = object
    entities: seq[SpaceEntity]
    nameToEntityInd: Table[string, int]
    nameCount: CountTable[string]

  World* = object
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
  world.activeChunks.add Chunk(entities: @[SpaceEntity(name: playerName)], nameToEntityInd: {playerName: 0}.toTable())

  const
    entityNames = ["Freighter", "Asteroid", "Carrier", "Hauler", "Unknown"]
    factionNames = ["Alliance", "Gerenfi", "Kulvan", "Ura Space Allies"]

  for _ in 0..world.randState.rand(5..40):
    let
      selectedName = world.randState.sample(entityNames)
      name = selectedName & $world.activeChunks[0].nameCount.getOrDefault(selectedName)
      x = world.randState.rand(-1000d..1000d)
      y = world.randState.rand(-1000d..1000d)
      vel = world.randState.rand(1d..10d)
      faction = world.randState.sample(factionNames)



    world.activeChunks[0].entities.add SpaceEntity(name: name, x: x, y: y, velocity: vel, faction: faction)
    world.activeChunks[0].nameToEntityInd[name] = world.activeChunks[0].entities.high
    inc world.activeChunks[0].nameCount, selectedName

proc update*(world: var World, dt: float32) =
  for entity in world.activeChunks[0].entities.mitems:
    entity.x += dt * entity.velocity

iterator nonPlayerEntities*(world: World): lent SpaceEntity =
  let playerInd = world.activeChunks[0].nameToEntityInd[world.playerName]
  for i, ent in world.activeChunks[0].entities:
    if i != playerInd:
      yield ent
