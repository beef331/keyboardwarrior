import insensitivestrings

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

  InventoryEntry* = ref object
    kind*: InventoryKind
    name*: InsensitiveString
    weight*: int
    operationResult*: array[ItemOperation, InventoryEntry] # What item do we get for this operation
    operationCount*: array[ItemOperation, int] # How many do we get for this operation

  InventoryItem* = object
    entry*: InventoryEntry # Do not need to copy this part
    amount*: int
