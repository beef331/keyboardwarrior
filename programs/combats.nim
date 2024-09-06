{.used.}
import gamestates
import std/[strscans, setutils, strbasics]
import "$projectdir"/data/[spaceentity, insensitivestrings]
import "$projectdir"/utils/todoer

type
  Target = object
  Fire = object

proc handler(_: Target, gameState: var GameState, input: string) =
  if (var (success, bay, target) = input.scanTuple("$s$+ $s$+$."); success):
    target.strip()
    var found = false
    for sys in gameState.activeShipEntity.systemsOf({WeaponBay, ToolBay}):
      if sys.name == InsensitiveString(bay):
        found = true
        if not gameState.world.entityExists(target):
          gameState.writeError("No target named: '" & target & "'.")
        else:
          if sys.kind == ToolBay:
            sys.toolTarget = target
            sys.flags.incl Toggled
          else:
            sys.weaponTarget = target
        break


    if not found:
      gameState.writeError("No bay named: '" & bay & "'.")


  else:
    gameState.writeError("Expected: 'target WeaponBay Target'.")

iterator bays(gameState: GameState, hasTarget = false): string =
  for wBay in gameState.activeShipEntity.poweredSystemsOf({WeaponBay, ToolBay}):
    if (hasTarget and wbay.weaponTarget != "") or not hasTarget:
      yield string wbay.name

proc suggest(_: Target, gameState: GameState, input: string, ind: var int): string =
  case input.suggestIndex()
  of 0, 1:
    suggestNext(gameState.bays, input, ind)
  of 2:
    iterator entities(gameState: GameState): string =
      for ent in gameState.world.allInSensors(gameState.activeShip):
        yield ent.name
    suggestNext(gameState.entities, input, ind)
  else:
    ""

proc name(_: Target): string = "target"
proc help(_: Target): string = "Sets the target of a specific bay."
proc manual(_: Target): string = ""

proc handler(_: Fire, gameState: var GameState, input: string) =
  if (var (success, bay) = input.scanTuple("$s$+$."); success):
    bay.strip()
    var found = false
    for sys in gameState.activeShipEntity.systemsOf({WeaponBay, ToolBay}):
      if sys.name == InsensitiveString(bay):
        found = true
        if sys.kind == ToolBay:
          gameState.writeError("Cannot fire a toolbay.")
        elif Powered notin sys.flags:
          gameState.writeError("Cannot fire a unpowered weapon bay.")
        elif not gameState.world.entityExists(sys.weaponTarget):
          gameState.writeError("Invalid target")
        else:
          sys.flags[Toggled] = Toggled notin sys.flags
        break


    if not found:
      gameState.writeError("No bay named: '" & bay & "'")


  else:
    gameState.writeError("Expected: 'fire BayName'.")

proc suggest(_: Fire, gameState: GameState, input: string, ind: var int): string =
  case input.suggestIndex()
  of 0, 1:
    suggestNext(gameState.bays(true), input, ind)
  else:
    ""

proc name(_: Fire): string = "fire"
proc help(_: Fire): string = "Toggles the fire state of a weapon bay. If active shuts it off."
proc manual(_: Fire): string = ""

storeCommand Target().toTrait(CommandImpl)
storeCommand Fire().toTrait(CommandImpl)
