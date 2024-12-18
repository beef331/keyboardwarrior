import std/[hashes, strutils]

type InsensitiveString* = distinct string
converter toString*(str: InsensitiveString): lent string = string(str)
converter toString*(str: var InsensitiveString): var string = string(str)

proc `$`*(a: InsensitiveString): string {.borrow.}

proc `==`*(a, b: InsensitiveString): bool =
  cmpIgnoreStyle(a, b) == 0

proc hash*(str: InsensitiveString): Hash =
  for ch in str.items:
    let ch = ch.toLowerAscii()
    if ch != '_':
      result = result !& hash(ch)

  result = !$result

proc insStr*(s: sink string): InsensitiveString = InsensitiveString(s)


proc insensitiveParseEnum*[T: enum](val: string): T =
  for x in T:
    if InsensitiveString($x) == InsensitiveString(val):
      return x
  raise newException(ValueError, "No value named: " & val  & " in " & $T)
