{.used.}
import gamestates
import std/[strscans, setutils, strbasics, strformat, strutils, tables, enumerate]
import "$projectdir"/data/[spaceentity, insensitivestrings, worlds, inventories]
import "$projectdir"/utils/todoer
import "$projectdir"/screenutils/[styledtexts, texttables]
import pkg/[truss3D, chroma]

type
  Combat = object
  Fire = object
  TurnEnd = object
  Energy = object

  TargettingState = enum
    WeaponSelect
    EntitySelect

  Target = object
    selecting: TargettingState
    weaponSystem: CombatSystem
    weaponSelection: int
    entitySelection: int
    targetSelection: int
    entity: SpaceEntity
    target: InsensitiveString

  Activate = object

proc istr(input: string; target: var string, start: int): int =
  while start + result < input.len and input[result + start] notin WhiteSpace:
    target.add input[result + start]
    inc result

proc handler(_: Combat, gameState: var GameState, input: string) =
  var target = ""
  if input.scanf("$s${istr}", target):
    target.strip()
    if gameState.hasEntity(target, {Ship, Station}):
      gameState.world.enterCombat(gameState.activeShip, target)
      let combat = gameState.activeCombat()
      gamestate.buffer.put "Entered combat with: "
      for state in combat.entityToCombat.values:
        if state.entity != gameState.activeShip:
          gameState.buffer.put gameState.world.getEntity(state.entity).name, wrapped = true
          gameState.buffer.put " ", wrapped = true

      let pos = gameState.buffer.getPosition()
      gameState.buffer.setPosition(pos[0] - 1, pos[1])
      gameState.buffer.put "."
      gameState.buffer.newline()


    else:
      gameState.writeError(fmt"No ship or station named: '{target}' found.")
  else:
    gameState.writeError("Expected: 'combat target'.")

proc suggest(_: Combat, gameState: GameState, input: string, ind: var int): string =
  case input.suggestIndex()
  of 0, 1:
    iterator allShips(gameState: GameState): string =
      for ent in gameState.world.allInSensors(gameState.activeShip):
        if ent.kind in {Ship, Station}:
          yield ent.name
    suggestNext(gameState.allShips(), input, ind)
  else:
    ""

proc name(_: Combat): string = "combat"
proc help(_: Combat): string = "Start combat with a ship or station"
proc manual(_: Combat): string = ""

storeCommand Combat().toTrait(CommandImpl), {InWorld}

proc printCurrentEnergy(gameState: var GameState) =
  let
    combat = gameState.activeCombat()
    combatState = combat.entityToCombat[gameState.activeShip]

  const color = [
    Weapons: parseHtmlColor"orange",
    Shields: parseHtmlColor"blue",
    Logistics: parseHtmlColor"green",
    Engines: parseHtmlColor"yellow",
  ]


  gameState.buffer.put "Unallocated " & "■".repeat(combatState.energyCount)
  gameState.buffer.put "□".repeat(combatState.maxEnergyCount - combatState.energyCount), GlyphProperties(foreground: parseHtmlColor"grey")
  gameState.buffer.newline()

  for name, energy in combatState.energyDistribution:
    gameState.buffer.put $name & " " & "■".repeat(combatState.energyUsed[name]), GlyphProperties(foreground: color[name])
    let chargesUsed = energy - combatState.energyUsed[name]
    if chargesUsed > 0:
      gameState.buffer.put "■".repeat(energy - combatState.energyUsed[name]), GlyphProperties(foreground: color[name] * 0.4)
    gameState.buffer.put "□".repeat(combatState.maxEnergyCount - energy),  GlyphProperties(foreground: color[name] * 0.1)
    gameState.buffer.newline()


proc handler(_: Energy, gameState: var GameState, input: string) =
  var
    errored = false
    energy: string
    amount: int
  if input.isEmptyOrWhitespace():
    discard

  elif input.scanf("$s${istr}$s$i", energy, amount):
    try:
      let
        power = insensitiveParseEnum[CombatSystemKind](energy)
        combat = gameState.activeCombat()
        combatState = combat.entityToCombat[gameState.activeShip]
        maxEnergyForSystem = combatState.energyDistribution[power] + combatState.energyCount

      if amount < 0:
        errored = true
        gameState.writeError("Cannot set the power to below zero.")
      elif amount > maxEnergyForSystem:
        errored = true
        gameState.writeError(fmt"Cannot give the system more than {maxEnergyForSystem} with currrent energy distribution.")
      else:
        let toAdd = amount - combatState.energyDistribution[power]
        combatState.energyDistribution[power] += toAdd
        combatState.energyCount -= toAdd

    except CatchableError:
      errored = true
      gameState.writeError("Expected {Shield | Weapon | Logistics | Engine}.")
  else:
    errored = true
    gameState.writeError("Expected: 'energy {Shield | Weapon | Logistic | Engine} powerlevel'.")

  if not errored:
    gameState.printCurrentEnergy()


proc suggest(_: Energy, gameState: GameState, input: string, ind: var int): string =
  case input.suggestIndex()
  of 0, 1:
    iterator powerableSystems(_: GameState): string =
      for state in CombatSystemKind:
        yield $state
    suggestNext(gameState.powerableSystems(), input, ind)
  else:
    ""

proc name(_: Energy): string = "energy"
proc help(_: Energy): string = "Adjust energy level of systems"
proc manual(_: Energy): string = ""

storeCommand Energy().toTrait(CommandImpl), {InCombat}


proc chargeIndicator(i: int): StyledText =
  styledText("<text foreground=orange>" & "■".repeat(i) & "</text>")

const
  damageIcon = [
    DamageKind.Fire: "󱠇",
    "⚡",
    "",
    "",
  ]
  damageProps= [
    DamageKind.Fire: GlyphProperties(foreground: parseHtmlColor"Orange"),
    GlyphProperties(foreground: parseHtmlColor"Yellow"),
    GlyphProperties(foreground: parseHtmlColor"Cyan"),
    GlyphProperties(foreground: parseHtmlColor"Grey"),
  ]

proc damageFormat(d: DamageDealt): StyledText =
  for name, damage in d.pairs:
    result = result.add styledText(damageIcon[name], damageProps[name])
    result = result.add styledText($damage, damageProps[name])
    if name != DamageKind.high:
      result = result.add styledText(" ")

proc modifierFormat(d: DamageModifiers): StyledText =
  for name, damage in d.pairs:
    result = result.add styledText(damageIcon[name], damageProps[name])
    result = result.add styledText($damage & "x", damageProps[name])
    if name != DamageKind.high:
      result = result.add styledText(" ")

proc healthFormat(health: (int, int)): StyledText =
  result = result.add styledText($health[0], GlyphProperties(foreground: mix(parseHtmlColor"red", parseHtmlColor"lime", health[0] / health[1])))
  result = result.add styledText"/"
  result = result.add styledText($health[1], GlyphProperties(foreground: parseHtmlColor"lime"))


type WeaponDialog = object
  name {.tableAlign: alignLeft.}: string
  damage {.tableStringify: damageFormat.}: DamageDealt
  chargeTurns {.tableStringify: chargeIndicator, tableName: "󱤤".}: int
  chargeCost {.tableStringify: chargeIndicator, tableName: "󰟌".}: int
  activateCost {.tableStringify: chargeIndicator, tableName: "󰲅".}: int


type TargetDialog = object
  name {.tableAlign: alignLeft.}: string
  damageModifier {.tableStringify: modifierFormat.}: DamageModifiers
  health {.tableStringify: healthFormat.}: (int, int)

proc onExit(_: var Target, gameState: var GameState) = discard
proc update(targ: var Target, gameState: var GameState, truss: var Truss, dt: float32, flags: ProgramFlags) =
  let theState = gameState.activeCombatState()
  if TakeInput in flags:
    case targ.selecting
    of WeaponSelect:
      let targetableCount = theState.targetableCount()
      if truss.inputs.isDownRepeating(KeycodeDown):
        targ.weaponSelection = (targ.weaponSelection - 1 + targetableCount) mod targetableCount
      if truss.inputs.isDownRepeating(KeycodeUp):
        targ.weaponSelection = (targ.weaponSelection + 1 + targetableCount) mod targetableCount
      if truss.inputs.isDown(KeycodeReturn):
        targ.selecting = EntitySelect

    of EntitySelect:
      var entityCount = 0
      for entity in gameState.activeCombat().entityToCombat.keys:
        if targ.weaponSystem.canTarget(gameState.activeShip, entity):
          inc entityCount

      if truss.inputs.isDownRepeating(KeycodeLeft):
        targ.entitySelection = (targ.entitySelection - 1 + entityCount) mod entityCount
        targ.targetSelection = 0
      if truss.inputs.isDownRepeating(KeycodeRight):
        targ.entitySelection = (targ.entitySelection + 1 + entityCount) mod entityCount
        targ.targetSelection = 0

      var
        targetCount = 0
        i = 0
      for entity, combat in gameState.activeCombat().entityToCombat.pairs:
        if targ.weaponSystem.canTarget(gameState.activeShip, entity):
          if i == targ.entitySelection:
            targetCount = combat.systems.len
            break
          inc i

      if truss.inputs.isDownRepeating(KeycodeUp):
        targ.targetSelection = (targ.targetSelection - 1 + targetCount) mod targetCount
      if truss.inputs.isDownRepeating(KeycodeDown):
        targ.targetSelection = (targ.targetSelection + 1 + targetCount) mod targetCount

      if truss.inputs.isDown(KeycodeReturn):
        let combat = gameState.activeCombat()
        var i = 0
        for entity, state in combat.entityToCombat.pairs:
          if targ.weaponSystem.canTarget(gameState.activeShip, entity):
            if i == targ.entitySelection:
              targ.weaponSystem.target = entity
              for j, name in enumerate state.systems.keys:
                if j == targ.targetSelection:
                  targ.weaponSystem.targetSystem = name
                  break
              break
            inc i

        reset targ


  if Draw in flags:
    case targ.selecting:
    of WeaponSelect:
      var weapons: seq[WeaponDialog]
      for name, system in theState.systems.pairs:
        if Targetable in system.realSystem.flags:
          targ.weaponSystem = system
          weapons.add WeaponDialog(
            name: name.string,
            damage: system.realSystem.damageDealt,
            chargeTurns: system.realSystem.chargeTurns,
            chargeCost: system.realSystem.chargeEnergyCost,
            activateCost: system.realSystem.activateCost
          )

      gameState.buffer.printPaged(
        weapons,
        targ.weaponSelection,
        unselectedModifier = proc(props: var GlyphProperties) =
          props.foreground = props.foreground * 0.3f

        )
    else:
      let combat = gameState.activeCombat()
      var i = 0
      for entity, state in combat.entityToCombat.pairs:
        if targ.weaponSystem.canTarget(gameState.activeShip, entity):
          if i == targ.entitySelection:
            gameState.buffer.put("<")
            gamestate.buffer.put(gameState.world.getEntity(entity).name.string.center(gameState.buffer.lineWidth - 2))
            gameState.buffer.put(">")
            gameState.buffer.newLine()

            let theSys = targ.weaponSystem

            gameState.buffer.printPaged(
              [
                WeaponDialog(
                  name: theSys.realSystem.name.string,
                  damage: theSys.realSystem.damageDealt,
                  chargeTurns: theSys.realSystem.chargeTurns,
                  chargeCost: theSys.realSystem.chargeEnergyCost,
                  activateCost: theSys.realSystem.activateCost
                  )
              ],
              printHeader = false
            )


            var targetEntries: seq[TargetDialog]
            for name, system in state.systems.pairs:
              targetEntries.add TargetDialog(
                name: name.string,
                damageModifier: system.realSystem.damageModifier,
                health: (system.realSystem.currentHealth, system.realSystem.maxHealth)
              )

            gameState.buffer.printPaged(
              targetEntries,
              targ.targetSelection,
              unselectedModifier = proc(props: var GlyphProperties) =
                props.foreground = props.foreground * 0.3f
            )

          inc i




proc getFlags(_: Target): set[ProgramFlag] = discard

proc suggest(_: Target, gameState: GameState, input: string, ind: var int): string =
  discard
proc name(_: Target): string = "target"
proc handler(_: Target, gameState: var GameState, input: string) =
  gameState.enterProgram Target().toTrait(Program)
proc help(_: Target): string = "Sets the target of a weapon or tool to an entity's specific system."
proc manual(_: Target): string = ""

storeCommand Target().toTrait(CommandImpl), {InCombat}


proc handler(_: Fire, gameState: var GameState, input: string) =
  var systemName: InsensitiveString
  if input.scanf("$s${istr}", string(systemName)):
    let
      combat = gameState.activeCombat()
      state = combat.entityToCombat[gameState.activeShip]
    if systemName notin state.systems:
      gameState.writeError(fmt"Cannot fire non existent system named {systemName}")
      return


    case (let fireState = state.systems[systemName].fireState(); fireState)
    of NoTarget:
      gameState.writeError($fireState)
    of InsufficientlyCharged:
      gameState.writeError($fireState % $state.systems[systemName].turnsTillCharged())
    of None:
      {.warning: "Print out the target we're targetting".}
      let fireError = state.fire(systemName)
      if fireError != None:
        gameState.writeError($fireError)
      else:
        gameState.buffer.put(fmt"Initiated firing sequence of {systemName}")
        gameState.buffer.newLine()


  else:
    gameState.writeError("Expected: fire systemName")


proc suggest(_: Fire, gameState: GameState, input: string, ind: var int): string =
  case input.suggestIndex()
  of 0, 1:
    iterator fireableWeapons(gameState: GameState): string =
      let
        combat = gameState.activeCombat()
        state = combat.entityToCombat[gameState.activeShip]

      for name, system in state.systems.pairs:
        if system.fireState == None:
          yield name.string

    suggestNext(gameState.fireableWeapons(), input, ind)

  else:
    ""

proc name(_: Fire): string = "fire"
proc help(_: Fire): string = "Fire the desired system."
proc manual(_: Fire): string = ""

storeCommand Fire().toTrait(CommandImpl), {InCombat}


proc handler(_: TurnEnd, gameState: var GameState, input: string) =
  gameState.activeCombat.endTurn()

proc suggest(_: TurnEnd, gameState: GameState, input: string, ind: var int): string =
  ""

proc name(_: TurnEnd): string = "endturn"
proc help(_: TurnEnd): string = "ends the current turn"
proc manual(_: TurnEnd): string = ""

storeCommand TurnEnd().toTrait(CommandImpl), {InCombat}



proc handler(_: Activate, gameState: var GameState, input: string) =
  var weaponName: string
  if input.scanf("$s${istr}", weaponName):
    let
      combat = gameState.activeCombat()
      state = combat.entityToCombat[gameState.activeShip]

    if not state.hasSystemNamed(InsensitiveString weaponName):
      gameState.writeError(fmt"Cannot activate a non existent system: {weaponName}.")
      return

    let system = state.systems[InsensitiveString weaponName]

    case system.chargeState()
    of FullyCharged:
      gameState.writeError("Cannot charge system further")
    of NotCharged:
      let error = state.powerOn(InsensitiveString weaponName)
      if error == NotEnoughPower:
        gameState.writeError($error)
    else:
      gameState.writeError("Not a chargable system.")


  else:
    gameState.writeError("Expected: active weapon")

proc suggest(_: Activate, gameState: GameState, input: string, ind: var int): string =
  case input.suggestIndex()
  of 0, 1:
    iterator chargableWeapons(gameState: GameState): string =
      let
        combat = gameState.activeCombat()
        state = combat.entityToCombat[gameState.activeShip]

      for name, system in state.systems.pairs:
        if system.chargeState == NotCharged:
          yield name.string

    suggestNext(gameState.chargableWeapons(), input, ind)

  else:
    ""


proc name(_: Activate): string = "activate"
proc help(_: Activate): string = "Powers on a system"
proc manual(_: Activate): string = ""

storeCommand Activate().toTrait(CommandImpl), {InCombat}
