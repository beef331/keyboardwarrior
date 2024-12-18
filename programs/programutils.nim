import std/[os, strutils, tables, setutils]
import gamestates
import "$projectdir"/data/[spaceentity, insensitivestrings]
export EntityState

proc insensitiveStartsWith*(a, b: openArray[char]): bool =
  if a.len < b.len:
    false
  else:
    for i, x in b:
      if x.toLowerAscii() != a[i].toLowerAscii():
        return false
    true

template suggestNext*(iter: iterable[string], input: string, ind: var int): string =
  var toComplete = ""
  for word in input.rsplit(WhiteSpace):
    toComplete = word
    break

  var
    res = ""
    found = false
    foundInds = 0

  for name in iter:
    if name.insensitiveStartsWith(toComplete) or toComplete.len == 0:
      if foundInds == (ind + 1):
        found = true
        inc ind
        res = name[toComplete.len..^1]
        break
      if res == "":
        res = name[toComplete.len..^1]
      inc foundInds

  if not found:
    ind = 0
  res

proc suggestIndex*(input: string): int =
  for word in input.rSplit(Whitespace): # Not ideal but less allocaty than `split: seq[string]`
    if word.len > 0:
      inc result
  if input.endsWith(' '):
    inc result

proc storecommand*(cmd: Command, usableIn: set[EntityState] = EntityState.fullSet()) =
  for state in usableIn:
    if cmd.name().InsensitiveString in defaultHandlers[state]:
      raise newException(ValueError, "Attempting to readd command: " & cmd.name())
    defaultHandlers[state][cmd.name().InsensitiveString] = cmd





