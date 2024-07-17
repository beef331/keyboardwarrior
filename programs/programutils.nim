import std/[macros, os, strutils]
import gamestates

var storedCommands: seq[Command]

proc insensitiveStartsWith*(a, b: openArray[char]): bool =
  if a.len < b.len:
    false
  else:
    for i, x in b:
      if x.toLowerAscii() != a[i].toLowerAscii():
        return false
    true


proc command*(
  name, help: string,
  handler: CommandHandler,
  manual = "",
  suggest = (proc(gs: GameState, input: string, ind: var int): string) nil
) =
  storedCommands.add Command(
    name: name,
    help: help,
    handler: handler,
    manual: manual,
    suggest: suggest
  )

iterator commands*(): Command =
  for command in storedCommands:
    yield command

macro importAllCommands*(): untyped =
  result = nnkImportStmt.newNimNode()
  for file in walkDir(currentSourcePath().parentDir()):
    let name = file.path.splitFile().name
    if file.path.endsWith(".nim") and name notin ["gamestates", "programutils"]:
      result.add ident(name)

