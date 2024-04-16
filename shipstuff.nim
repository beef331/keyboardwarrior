type
  BayKind = enum
    Nothing
    Rocket
    Turret

  AmmoKind = enum
    Bullet
    Rail
    Nuclear

  EntityFlag = enum
    Powered
    Damaged
    Jammed

  EntityFlags = set[EntityFlag]

  Entity = object of RootObj
    name: string

  PoweredEntity = object of Entity
    flags: EntityFlags

  LimitedVal[T] = object
    min, max: T
    val: T

  Bay = object of PoweredEntity
    target: string
    case kind: BayKind
    of Turret, Rocket:
      ammo: LimitedVal[int]
      ammoKind: AmmoKind
    else:
      discard

  Thing = object of Entity
    volume: int

  Room = object of PoweredEntity
    position: int
    inventory: seq[Thing]

  DoorState = enum
    Closed
    Opened

  Door = object of PoweredEntity
    state: DoorState

  SystemKind = enum
    Networking
    AutoTargetting
    AutoLoader
    JamProtection
    Sensors


  ShipSystem = object of PoweredEntity
    case kind: SystemKind
    of Sensors:
      sensorRange: int
    else: discard


  Ship = object of Entity
    weaponBays: seq[Bay]
    rooms: seq[Room]
    door: seq[Door]
    systems: seq[ShipSystem]
    fuel: LimitedVal[int]

proc hasSystem(ship: Ship, kind: SystemKind): bool =
  for system in ship.systems:
    if system.kind == kind:
      return true


proc load(ship: var Ship, name: string, kind: AmmoKind) =
  for bay in ship.weaponBays.mitems:
    if bay.name == name:
      if bay.ammo.val == 0:
        ## load the ammo
      elif not ship.hasSystem(JamProtection):
        bay.flags.incl Jammed

proc unjam(ship: var Ship, name: string) =
  for bay in ship.weaponBays.mitems:
    if bay.name == name:
      bay.flags.excl Jammed
