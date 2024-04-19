import std/[macros, os, strutils]
import gamestates

var storedCommands: seq[Command]

proc command*(name, help: string, handler: CommandHandler) =
  storedCommands.add Command(name: name, help: help, handler: handler)

iterator commands*(): Command =
  for command in storedCommands:
    yield command

macro importAllCommands*(): untyped =
  result = nnkImportStmt.newNimNode()
  for file in walkDir(currentSourcePath().parentDir()):
    let name = file.path.splitFile().name
    if file.path.endsWith(".nim") and name notin ["gamestates", "programutils"]:
      result.add ident(name)

