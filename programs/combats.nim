import gamestates
import std/strscans
import "$projectdir"/data/[spaceentity, insensitivestrings]
import "$projectdir"/utils/todoer

proc targetHandler(gameState: var GameState, input: string) =
  if (let (success, bay, target) = input.scanTuple("$s$+ $s$+$."); success):
    var found = false
    for sys in gameState.activeShipEntity.systemsOf({WeaponBay, ToolBay}):
      if sys.name == InsensitiveString(bay):
        found = true
        todo("Set bay target.")

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
        if sys.kind == ToolBay:
          gameState.writeError("Cannot fire a toolbay.")
        else:
          found = true
          todo("Fire weapon bay.")

    if not found:
      gameState.writeError("No bay named: '" & bay & "'.\n")


  else:
    gameState.writeError("Expected: 'fire BayName'\n")

command(
  "fire",
  "Fire bay at current target.",
  fireHandler
)
