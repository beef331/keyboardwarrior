import gamestates
import std/[strscans, setutils]
import "$projectdir"/data/[spaceentity, insensitivestrings]
import "$projectdir"/utils/todoer

proc targetHandler(gameState: var GameState, input: string) =
  if (let (success, bay, target) = input.scanTuple("$s$+ $s$+$."); success):
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


command(
  "target",
  "Sets the target of a specific weapon.",
  targetHandler
)

proc fireHandler(gameState: var GameState, input: string) =
  if (let (success, bay) = input.scanTuple("$s$+$."); success):
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

command(
  "fire",
  "Toggles the fire state of a weapon bay. If active shuts it off.",
  fireHandler
)
