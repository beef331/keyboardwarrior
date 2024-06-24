import std/[tables, random, hashes, sysrand, math]
import ../screenutils/screenrenderer
import quadtrees
import insensitivestrings

type
  InventoryItem* = object
    name*: string
    count*: int
    cost*: int
    weight*: int

  Compartment* = object
    inventory*: seq[InventoryItem]
    maxLoad*: int

  EntityKind* = enum
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

  SystemKind* = enum
    Sensor
    WeaponBay ## Turrets, Missiles bays, ...
    ToolBay ## Drills, welders, ...
    Thruster
    Shield
    Nanites
    AutoLoader
    AutoTargetting
    Hacker
    Room
    Generator ## Generates power

  WeaponKind* = enum
    Bullet
    Guass
    RocketVolley
    Missile
    Nuke

  ToolKind* = enum
    Drill
    Welder

  SystemFlag* = enum
    Powered
    Jammed
    Toggled

  System* = object
    name*: InsensitiveString
    powerUsage*: int # Generated when a generator
    flags*: set[SystemFlag] = {Powered}
    interactionTime*: float32
    interactionDelay*: float32
    case kind*: SystemKind
    of Sensor:
      sensorRange*: int
    of WeaponBay:
      weaponTarget*: string
      weaponkind*: WeaponKind
      maxAmmo*: int
      currentAmmo*: int
    of ToolBay:
      toolTarget*: string # Use node id instead?
    of Shield, Nanites:
      currentShield*, maxShield*: int
      regenRate*: int
    of Thruster:
      acceleration*: float32
      maxSpeed*: float32
    of AutoLoader:
      discard
    of AutoTargetting:
      autoTarget*: string
    of Hacker:
      hackSpeed*: int
      hackRange*: int
    of Room:
      inventory*: Compartment
    of Generator:
      discard

  ShipData* = ref object # Pointer indirection to reduces size of SpaceEntity
    glyphProperties*: GlyphProperties
    systems*: seq[System]

  SpaceEntity* = object
    node: int # For the tree
    name*: string
    faction*: Faction
    x*, y*: float32
    velocity*: float32
    maxSpeed*: float32
    heading: float32
    case kind*: EntityKind
    of Ship, Station:
      shipData*: ShipData
    of Asteroid:
      resources: seq[InventoryItem]
    of Projectile:
      projKind: WeaponKind

  Chunk = object
    entities: QuadTree[SpaceEntity]
    nameToEntityInd: Table[InsensitiveString, QuadTreeIndex]
    nameCount: CountTable[InsensitiveString]

  World* = object
    player: QuadTreeIndex
    playerName: string # GUID no other ship can use this
    seed: int # Start seed to allow reloading state from chunks
    randState*: Rand
    activeChunk: Chunk

  NotSystem* = distinct set[SystemKind]

proc canHack*(spaceEntity: SpaceEntity): bool =
  if spaceEntity.kind in {Ship, Station}:
    for sys in spaceEntity.shipData.systems:
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
      shipData:
        ShipData(
          glyphProperties: GlyphProperties(foreground: parseHtmlColor("white"), background: parseHtmlColor("black")),
          systems: @[
            System(name: insStr"Sensor Array", kind: Sensor, sensorRange: 75, powerUsage: 100),
            System(name: insStr"Hacker", kind: Hacker, hackSpeed: 1, hackRange: 100, powerUsage: 25),
            System(name: insStr"Warp Core", kind: Generator, powerUsage: 300),
            System(name: insStr"WBay1", kind: WeaponBay, interactionDelay: 0.7f, currentAmmo: 100)
          ]
        )
    )
  world.activeChunk = Chunk(entities: qt, nameToEntityInd: {insStr playerName: world.player}.toTable())

  const entityNames = ["Freighter", "Asteroid", "Carrier", "Hauler", "Unknown"]

  for _ in 0..1000:
    let
      selectedName = world.randState.sample(entityNames)
      name = selectedName & $world.activeChunk.nameCount.getOrDefault(insStr selectedName)
      x = world.randState.rand(100d..900d)
      y =  world.randState.rand(100d..900d)
      vel =  world.randState.rand(0.1d..0.3d)
      faction = world.randState.rand(Faction)
      heading = world.randState.rand(0d..Tau)

    var ent = SpaceEntity(
      kind: if selectedName == entityNames[1]: Asteroid else: Ship,
      name: name,
      x: x,
      y: y,
      velocity: vel,
      maxSpeed: world.randState.rand(vel .. 5d),
      faction: faction,
      heading: heading,
    )



    if ent.kind in {Ship, Station}:
      let powered =
        if world.randState.rand(0..100) > 20:
          {Powered}
        else:
          {}

      ent.shipData = ShipData(
        glyphProperties: GlyphProperties(
          foreground: color(world.randState.rand(0.3f..1f), world.randState.rand(0.3f..1f), world.randState.rand(0.3f..1f))
        ),
        systems: @[
          System(name: insStr"Sensor Array", kind: Sensor, sensorRange: 75, powerUsage: 100),
          System(name: insStr"Hacker", kind: Hacker, hackSpeed: 1, hackRange: 100, powerUsage: 25, flags: powered),
          System(name: insStr"Warp Core", kind: Generator, powerUsage: 300),
        ]
      )

    world.activeChunk.nameToEntityInd[insStr name] = world.activeChunk.entities.add ent



    inc world.activeChunk.nameCount, insStr selectedName


proc player*(world: World): lent SpaceEntity =
  world.activeChunk.entities[world.player]

proc getEntity*(world: World, name: string): lent SpaceEntity =
  world.activeChunk.entities[world.activeChunk.nameToEntityInd[insStr name]]

proc getEntity*(world: var World, name: string): var SpaceEntity =
  world.activeChunk.entities[world.activeChunk.nameToEntityInd[insStr name]]

proc entityExists*(world: World, name: string): bool = insStr(name) in world.activeChunk.nameToEntityInd
proc entityExists*(world: World, name: InsensitiveString): bool = name in world.activeChunk.nameToEntityInd


iterator systemsOf*(entity: SpaceEntity, filter: set[SystemKind] | NotSystem): lent System =
  for system in entity.shipData.systems:
    when filter is NotSystem:
      if system.kind notin filter.set[:SystemKind]:
        yield system
    else:
      if system.kind in filter:
        yield system

iterator systemsOf*(entity: var SpaceEntity, filter: set[SystemKind] | NotSystem): var System =
  for system in entity.shipData.systems.mitems:
    when filter is NotSystem:
      if system.kind notin filter.set[:SystemKind]:
        yield system
    else:
      if system.kind in filter:
        yield system

iterator poweredSystemsOf*(entity: SpaceEntity, filter: set[SystemKind] | NotSystem): lent System =
  for system in entity.shipData.systems:
    if Powered in system.flags:
      when filter is NotSystem:
        if system.kind notin filter.set[:SystemKind]:
          yield system
      else:
        if system.kind in filter:
          yield system

iterator poweredSystemsOf*(entity: var SpaceEntity, filter: set[SystemKind] | NotSystem): var System =
  for system in entity.shipData.systems.mitems:
    if Powered in system.flags:
      when filter is NotSystem:
        if system.kind notin filter.set[:SystemKind]:
          yield system
      else:
        if system.kind in filter:
          yield system

iterator poweredSystems*(entity: SpaceEntity): lent System =
  for system in entity.shipData.systems:
    if Powered in system.flags:
      yield system

iterator unpoweredSystems*(entity: SpaceEntity): lent System =
  for system in entity.shipData.systems:
    if Powered notin system.flags:
      yield system

proc generatedPower*(entity: SpaceEntity): int =
  for generator in entity.systemsOf({Generator}):
    result.inc generator.powerUsage

proc consumedPower*(entity: SpaceEntity): int =
  for consumer in entity.systemsOf(NotSystem {Generator}):
    if Powered in consumer.flags:
      result.inc consumer.powerUsage

proc hasPoweredSystem*(entity: SpaceEntity, sys: SystemKind): bool =
  for system in entity.poweredSystemsOf({sys}):
    return true

iterator nonPlayerEntities*(world: World): lent SpaceEntity =
  for i, ent in world.activeChunk.entities.inRangePairs(450, 450, 100, 100):
    if i != world.player:
      yield ent

proc sensorRange*(ent: SpaceEntity): int =
  for sys in ent.poweredSystemsOf({Sensor}):
    result = max(sys.sensorRange, result)

iterator allInSensors*(world: World, entity: string): lent SpaceEntity =
  let
    filtered = world.activeChunk.nameToEntityInd[InsensitiveString entity]
    ent = world.activeChunk.entities[filtered]
    sensorRange = ent.sensorRange()
    sqrRange = sensorRange * sensorRange

  for i, otherEnt in world.activeChunk.entities.inRangePairs(ent.x.int, ent.y.int, sensorRange, sensorRange):
    if i != filtered:
      let sqrDist = (ent.x - otherEnt.x) * (ent.x - otherEnt.x) + (ent.y - otherEnt.y) * (ent.y - otherEnt.y)
      if sqrDist <= sqrRange.float32:
        yield otherEnt


proc fireWeapon(world: var World, ent: SpaceEntity, sys: var System, dt: float32) =
  assert Powered in sys.flags
  assert Toggled in sys.flags
  assert sys.kind == WeaponBay

  if sys.currentAmmo == 0:
    sys.flags.excl Toggled
    return

  sys.interactionTime -= dt
  if sys.interactionTime <= 0:
    var counter {.global.}: int = 0
    let name = "bullet" & $counter
    inc counter
    let
      target = world.getEntity sys.weaponTarget
      heading = arctan2(target.y - ent.y, target.x - ent.x)


    world.activeChunk.nameToEntityInd[insStr name] = world.activeChunk.entities.add SpaceEntity(
        kind: Projectile,
        name: name,
        x: ent.x,
        y: ent.y,
        velocity: 10,
        maxSpeed: 10,
        heading: heading,
      )

    dec sys.currentAmmo

    if sys.currentAmmo == 0:
      sys.flags.excl Toggled

    sys.interactionTime = sys.interactionDelay




proc update*(world: var World, dt: float32) =
  for entity in world.activeChunk.entities.mitems:
    let
      xOffset = cos(entity.heading)
      yOffset = sin(entity.heading)
    entity.x += dt * entity.velocity * xOffset
    entity.y += dt * entity.velocity * yOffset
    if entity.kind == Ship:
      for system in entity.poweredSystemsOf({WeaponBay}):
        if Toggled in system.flags:
          fireWeapon(world, entity, system, dt)



  for toMove in world.activeChunk.entities.reposition():
    discard toMove # TODO: Move this to the next chunk
