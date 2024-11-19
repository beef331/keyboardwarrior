import inventories, spaceentity, insensitivestrings, combatstates
import std/[options, hashes, tables]

type
  Location* = object
    name*: InsensitiveString
    id*: LocationId
    x*, y*: int
    entities*: seq[SpaceEntity] # Use a quad tree?
    neighbours*: array[10, Option[LocationId]]
    combats*: seq[Combat] # If player is not in it, slowly tick it along simulating combat
    nameCount*: CountTable[string]

proc nextName*(loc: var Location, name: string): string =
  result = name
  let count = loc.nameCount.getOrDefault(name)
  if count != 0:
    result.add $count

  inc loc.nameCount, name
