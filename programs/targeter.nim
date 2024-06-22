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
