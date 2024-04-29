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
    Projectile
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

  SystemKind = enum
    Sensor
    WeaponBay # Turrets, Missiles bays, ...
    ToolBay # Drills, welders, ...
    Thruster
    Shield
    Nanites
    AutoLoader
    AutoTargetting
    Hacker
    Room

  WeaponKind = enum
    Bullet
    Guass
    RocketVolley
    Missile
    Nuke

  ToolKind = enum
    Drill
    Welder

  SystemFlag = enum
    Powered
    Jammed

  System = object
    name: string
    powerUsage: int
    flags: set[SystemFlag]
    case kind: SystemKind
    of Sensor:
      sensorRange: int
    of WeaponBay:
      weaponTarget: string
      weaponkind: WeaponKind
      maxAmmo: int
      currentAmmo: int
    of ToolBay:
      toolTarget: string # Use node id instead?
    of Shield, Nanites:
      currentShield, maxShield: int
      regenRate: int
    of Thruster:
      acceleration: float32
      maxSpeed: float32
    of AutoLoader:
      discard
    of AutoTargetting:
      autoTarget: string
    of Hacker:
      hackSpeed: int
      hackRange: int
    of Room:
      inventory: Compartment

  SpaceEntity* = object
    node: int # For the tree
    name*: string
    faction*: Faction
    x*, y*: float32
    velocity*: float32
    maxSpeed*: float32
    heading: float32
    case kind: EntityKind
    of Ship, Station:
      systems: seq[System]
    of Asteroid:
      resources: seq[InventoryEntry]
    of Projectile:
      projKind: WeaponKind

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

proc canHack*(spaceEntity: SpaceEntity): bool =
  if spaceEntity.kind in {Ship, Station}:
    for sys in spaceEntity.systems:
      if sys.kind == Hacker and Powered in sys.flags:
        return true


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
  world.player = qt.add:
    SpaceEntity(
      kind: Ship,
      name: playerName,
      x: 500,
      y: 500,
      maxSpeed: 3,
      systems: @[
        System(kind: Sensor, sensorRange: 100),
        System(kind: Hacker, hackSpeed: 1, hackRange: 100)
      ]
    )
  world.activeChunks.add Chunk(entities: qt, nameToEntityInd: {playerName: world.player}.toTable())

  const entityNames = ["Freighter", "Asteroid", "Carrier", "Hauler", "Unknown"]

  for _ in 0..1000:
    let
      selectedName = world.randState.sample(entityNames)
      name = selectedName & $world.activeChunks[0].nameCount.getOrDefault(selectedName)
      x = world.randState.rand(100d..900d)
      y =  world.randState.rand(100d..900d)
      vel =  world.randState.rand(1d..5d)
      faction = world.randState.rand(Faction)
      heading = world.randState.rand(0d..Tau)

    world.activeChunks[0].nameToEntityInd[name] = world.activeChunks[0].entities.add SpaceEntity(
      kind: if selectedName == entityNames[1]: Asteroid else: Ship,
      name: name,
      x: x,
      y: y,
      velocity: vel,
      maxSpeed: rand(vel .. 5d),
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
