import std/[tables, random, hashes, sysrand, math]
import ../screenutils/screenrenderer
import quadtrees, inventories, insensitivestrings

type
  LocationId* = distinct int

  EntityKind* = enum
    Asteroid
    Ship
    Station
    OreProcessor = "Ore-Processor"

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
    Inventory
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
      toolRange*: int
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
    of Inventory:
      inventory*: Table[InsensitiveString, InventoryItem]
      maxWeight*: int # Exceeding this causes the ship to slow down
    of Generator:
      discard

  ShipData* = ref object # Pointer indirection to reduces size of SpaceEntity
    glyphProperties*: GlyphProperties
    systems*: seq[System]

  EntityState* = enum
    InWorld
    InCombat

  SpaceEntity* = object
    location*: LocationId # Which node are we in?
    locationIndex*: int # What is the entity index in this location?
    currentHull*: int
    maxHull*: int
    state*: EntityState
    name*: string
    faction*: Faction
    x*, y*: float32
    velocity*: float32
    maxSpeed*: float32
    heading*: float32
    case kind*: EntityKind
    of Ship, Station:
      shipData*: ShipData
    of Asteroid:
      resources*: seq[InventoryItem]
    of OreProcessor:
      smeltOptions*: seq[(int, InventoryEntry)]

  NotSystem* = distinct set[SystemKind]

proc currentWeight*(system: System): int =
  assert system.kind == Inventory
  for x in system.inventory.values:
    result += x.entry.weight * x.amount

proc canHack*(spaceEntity: SpaceEntity): bool =
  if spaceEntity.kind in {Ship, Station}:
    for sys in spaceEntity.shipData.systems:
      if sys.kind == Hacker and Powered in sys.flags:
        return true

proc weight*(spaceEntity: SpaceEntity): int =
  case spaceEntity.kind
  of Asteroid:
    for x in spaceEntity.resources:
      result += x.entry.weight * x.amount
  else:
    assert false, "Unimplemented weight for: " & $spaceEntity.kind

iterator systemsOf*(entity: SpaceEntity, filter: set[SystemKind] | NotSystem): lent System =
  if entity.shipData != nil:
    for system in entity.shipData.systems:
      when filter is NotSystem:
        if system.kind notin filter.set[:SystemKind]:
          yield system
      else:
        if system.kind in filter:
          yield system

iterator systemsOf*(entity: var SpaceEntity, filter: set[SystemKind] | NotSystem): var System =
  if entity.shipData != nil:
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

proc sensorRange*(ent: SpaceEntity): int =
  for sys in ent.poweredSystemsOf({Sensor}):
    result = max(sys.sensorRange, result)
