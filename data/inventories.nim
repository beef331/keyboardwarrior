import insensitivestrings
import std/[tables]

type
  ItemOperation* = enum
    Smelt
    Upgrade

  InventoryKind* = enum
    Ore
    Ingot
    ShipComponent
    Ammo
    Food

  InventoryEntry* = ref object # reference to ensure we do not have two of the same item
    kind*: InventoryKind
    name*: InsensitiveString
    flavourText*: string
    weight*: int
    operationResult*: array[ItemOperation, InventoryEntry] # What item do we get for this operation
    operationCount*: array[ItemOperation, int] # How many do we get for this operation

  InventoryItem* = object
    entry*: InventoryEntry
    amount*: int

  SystemKind* = enum
    Hull
    Sensor
    WeaponBay ## Turrets, Missiles bays, ...
    ToolBay ## Drills, welders, ...
    Thruster
    Shield
    Nanites
    Hacker
    Inventory
    Generator ## Generates power

  DamageKind* = enum
    Fire
    Shock
    Cryo
    Kinetic

  WeaponKind* = enum
    Bullet
    Gauss
    RocketVolley
    Missile

  ToolKind* = enum
    Drill
    Welder

  SystemFlag* = enum
    Powered
    Jammed
    Toggled
    Targetable
    TargetSelf
    TargetOther

  DamageModifiers* = array[DamageKind, float32]
  DamageDealt* = array[DamageKind, int]

  System* = ref object # yet another ref, my cache coherency will cry
    name*: InsensitiveString
    flags*: set[SystemFlag] = {Powered}
    flavourText*: string
    currentHealth*: int
    maxHealth*: int
    activateCost*: int # how many blocks does it cost
    chargeEnergyCost*: int # how many blocks does this cost to use
    chargeTurns*: int # how many turns does it take to charge?
    damageModifier*: DamageModifiers = [Fire: 1f, 1, 1, 1] # How much damage do we take per type
    damageDealt*: DamageDealt

    case kind*: SystemKind
    of Sensor:
      sensorRange*: int
    of WeaponBay:
      weaponkind*: WeaponKind
      damageDelay*: int # how many turns does this wait for damage?
      damageTicks: int
      timeTilDamage*: int
      attackRange*: int
      aoeRange*: int
    of ToolBay:
      toolTarget*: string # Use node id instead?
    of Shield, Nanites:
      currentShield*, maxShield*: int
      regenRate*: int
    of Thruster:
      acceleration*: float32
      maxSpeed*: float32
    of Hacker:
      hackSpeed*: int
      hackRange*: int
    of Inventory:
      inventory*: Table[InsensitiveString, InventoryItem]
      maxWeight*: int # Exceeding this causes the ship to slow down
    of Generator:
      powerGeneration*: int
    of Hull:
      discard


proc doesCharge*(system: System): bool = system.chargeTurns > 0
