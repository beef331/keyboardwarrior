import gamestates
import std/[strscans, setutils, strbasics]
import "$projectdir"/data/[spaceentity, insensitivestrings]
import "$projectdir"/utils/todoer

proc targetHandler(gameState: var GameState, input: string) =
  if (var (success, bay, target) = input.scanTuple("$s$+ $s$+$."); success):
    target.strip()
    var found = false
    for sys in gameState.activeShipEntity.systemsOf({WeaponBay, ToolBay}):
      if sys.name == InsensitiveString(bay):
        found = true
        if not gameState.world.entityExists(target):
          gameState.writeError("No target named: '" & target & "'.\n")
        else:
          sys.weaponTarget = target
        break


    if not found:
      gameState.writeError("No bay named: '" & bay & "'.\n")


  else:
    gameState.writeError("Expected: 'target WeaponBay Target'\n")

iterator bays(gameState: GameState, hasTarget = false): string =
  for wBay in gameState.activeShipEntity.poweredSystemsOf({WeaponBay, ToolBay}):
    if (hasTarget and wbay.weaponTarget != "") or not hasTarget:
      yield string wbay.name

proc targetSuggest(gameState: GameState, input: string, ind: var int): string =
  case input.suggestIndex()
  of 2:

    suggestNext(gameState.bays, input, ind)
  of 3:
    iterator entities(gameState: GameState): string =
      for ent in gameState.world.allInSensors(gameState.activeShip):
        yield ent.name
    suggestNext(gameState.entities, input, ind)
  else:
    ""


command(
  "target",
  "Sets the target of a specific weapon.",
  targetHandler,
  suggest = targetSuggest
)

proc fireHandler(gameState: var GameState, input: string) =
  if (var (success, bay) = input.scanTuple("$s$+$."); success):
    bay.strip()
    var found = false
    for sys in gameState.activeShipEntity.systemsOf({WeaponBay, ToolBay}):
      if sys.name == InsensitiveString(bay):
        found = true
        if sys.kind == ToolBay:
          gameState.writeError("Cannot fire a toolbay.\n")
        elif Powered notin sys.flags:
          gameState.writeError("Cannot fire a unpowered weapon bay.\n")
        elif not gameState.world.entityExists(sys.weaponTarget):
          gameState.writeError("Invalid target.\n")
        else:
          sys.flags[Toggled] = Toggled notin sys.flags
        break


    if not found:
      gameState.writeError("No bay named: '" & bay & "'.\n")


  else:
    gameState.writeError("Expected: 'fire BayName'\n")

proc fireSuggest(gameState: GameState, input: string, ind: var int): string =
  case input.suggestIndex()
  of 2:
    suggestNext(gameState.bays(true), input, ind)
  else:
    ""

command(
  "fire",
  "Toggles the fire state of a weapon bay. If active shuts it off.",
  fireHandler,
  suggest = fireSuggest
)
