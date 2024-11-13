{.used.}
import gamestates
import std/[strscans, setutils, strbasics, strformat, strutils, tables, enumerate, options]
import "$projectdir"/data/[spaceentity, insensitivestrings, worlds, inventories]
import "$projectdir"/utils/todoer
import "$projectdir"/screenutils/[styledtexts, texttables]
import pkg/[truss3D, chroma]

type
  Combat = object
  Fire = object
  TurnEnd = object
  Energy = object
    selected: int = 1

  Action = object

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
    tickerProgress: float32 = 0

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


const systemColor = [
  Weapons: parseHtmlColor"orange",
  Shields: parseHtmlColor"blue",
  Logistics: parseHtmlColor"green",
  Engines: parseHtmlColor"yellow",
]


proc onExit(_: var Energy, gameState: var GameState) = discard

type EnergyDialog = object
  system: StyledText
  kind {.tableSkip.}: Option[CombatSystemKind]
  allocated {.tableName: "󰲅".}: int
  used {.tableSkip.}: int
  total {.tableSkip.}: int

proc tablify(allocated: int, data: EnergyDialog): StyledText =
  if data.kind.isNone:
    result.add "■".repeat(allocated).styledText()
    result.add "□".repeat(data.total - allocated).styledText()
  else:
    let kind = data.kind.get()
    if data.used > 0:
      result.add "■".repeat(data.used).styledText(GlyphProperties(foreground: systemColor[kind]))
    let unusedAllocated = allocated - data.used
    if unusedAllocated > 0:
      result.add "■".repeat(allocated - data.used).styledText(GlyphProperties(foreground: systemColor[kind] - 0.3))
    result.add "□".repeat(data.total - allocated).styledText(GlyphProperties(foreground: systemColor[kind] - 0.3))


proc update(energy: var Energy, gameState: var GameState, truss: var Truss, dt: float32, flags: ProgramFlags) =
  if TakeInput in flags:
    let
      selectedType = CombatSystemKind(energy.selected - 1)
      state = gameState.activeCombatState()

    if truss.inputs.isDownRepeating(KeycodeLeft) and state.energyDistribution[selectedType] > state.energyUsed[selectedType]:
      dec state.energyDistribution[selectedType]
      inc state.energyCount

    if truss.inputs.isDownRepeating(KeycodeRight) and state.energyCount > 0:
      inc state.energyDistribution[selectedType]
      dec state.energyCount

    const systemKindCount = CombatSystemKind.high.ord + 1
    if truss.inputs.isDownRepeating(KeycodeDown):
      energy.selected = 1 + ((selectedType.ord + 1 + systemKindCount) mod systemKindCount)

    if truss.inputs.isDownRepeating(KeycodeUp):
      energy.selected = 1 + ((selectedType.ord - 1 + systemKindCount) mod systemKindCount)

  if Draw in flags:
    let state = gameState.activeCombatState()
    var table: array[CombatSystemKind.high.int + 2, EnergyDialog]
    table[0] = EnergyDialog(
      system: styledText"Unallocated",
      kind: none(CombatSystemKind),
      allocated: state.energyCount,
      used: 0,
      total: state.maxEnergyCount
    )

    for name, energy in state.energyDistribution.pairs:
      table[name.ord + 1] = EnergyDialog(
        system: styledText($name, GlyphProperties(foreground: systemColor[name])),
        kind: some(name),
        allocated: energy,
        used: state.energyUsed[name],
        total: state.maxEnergyCount
      )

    gameState.buffer.printPaged(
      table,
      selected = energy.selected
    )


proc name(_: Energy): string = "energy"
proc getFlags(_: Energy): set[ProgramFlag] = {}

proc handler(_: Energy, gameState: var GameState, input: string) =
  gameState.enterProgram(Energy().toTrait(Program))

proc suggest(_: Energy, gameState: GameState, input: string, ind: var int): string =
  ""

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
    result.add styledText(damageIcon[name], damageProps[name])
    result.add styledText($damage, damageProps[name])
    if name != DamageKind.high:
      result.add styledText(" ")

proc modifierFormat(d: DamageModifiers): StyledText =
  for name, damage in d.pairs:
    result.add styledText(damageIcon[name], damageProps[name])
    result.add styledText($damage & "x", damageProps[name])
    if name != DamageKind.high:
      result.add styledText(" ")

proc healthFormat(health: (int, int)): StyledText =
  result.add styledText($health[0], GlyphProperties(foreground: mix(parseHtmlColor"red", parseHtmlColor"lime", health[0] / health[1])))
  result.add styledText"/"
  result.add styledText($health[1], GlyphProperties(foreground: parseHtmlColor"lime"))


type WeaponDialog = object
  name {.tableAlign: alignLeft.}: string
  damage {.tableStringify: damageFormat.}: DamageDealt
  chargeTurns {.tableStringify: chargeIndicator, tableName: "󱤤".}: int
  chargeCost {.tableStringify: chargeIndicator, tableName: "󰟌".}: int
  activateCost {.tableStringify: chargeIndicator, tableName: "󰲅".}: int
  target {.tableName: "󰓾".}: string


type TargetDialog = object
  name {.tableAlign: alignLeft.}: string
  damageModifier {.tableStringify: modifierFormat.}: DamageModifiers
  health {.tableStringify: healthFormat.}: (int, int)

proc onExit(_: var Target, gameState: var GameState) = discard

proc update(targ: var Target, gameState: var GameState, truss: var Truss, dt: float32, flags: ProgramFlags) =
  targ.tickerProgress += dt * 3

  let theState = gameState.activeCombatState()
  if TakeInput in flags:
    case targ.selecting
    of WeaponSelect:
      let targetableCount = theState.numberOfSystemsWithAny({TargetSelf, TargetOther})

      if truss.inputs.isDownRepeating(KeycodeDown):
        reset targ.tickerProgress
        targ.weaponSelection = (targ.weaponSelection - 1 + targetableCount) mod targetableCount

      if truss.inputs.isDownRepeating(KeycodeUp):
        reset targ.tickerProgress
        targ.weaponSelection = (targ.weaponSelection + 1 + targetableCount) mod targetableCount

      if truss.inputs.isDown(KeycodeReturn):
        reset targ.tickerProgress
        targ.selecting = EntitySelect
        var ind = 0
        for sys in theState.systems.values:
          if {TargetSelf, TargetOther} * sys.realSystem.flags != {}:
            if ind == targ.weaponSelection:
              targ.weaponSystem = sys
            inc ind


    of EntitySelect:
      var entityCount = 0
      for entity in gameState.activeCombat().entityToCombat.keys:
        if targ.weaponSystem.canTarget(gameState.activeShip, entity):
          inc entityCount

      if truss.inputs.isDownRepeating(KeycodeLeft):
        reset targ.tickerProgress
        targ.entitySelection = (targ.entitySelection - 1 + entityCount) mod entityCount
        targ.targetSelection = 0

      if truss.inputs.isDownRepeating(KeycodeRight):
        reset targ.tickerProgress
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
        reset targ.tickerProgress
        targ.targetSelection = (targ.targetSelection - 1 + targetCount) mod targetCount

      if truss.inputs.isDownRepeating(KeycodeDown):
        reset targ.tickerProgress
        targ.targetSelection = (targ.targetSelection + 1 + targetCount) mod targetCount

      if truss.inputs.isDown(KeycodeReturn):
        reset targ.tickerProgress
        let combat = gameState.activeCombat()
        for i, entity in enumerate targ.weaponSystem.targetableEntities(combat, gameState.activeShip):
          if i == targ.entitySelection:
            targ.weaponSystem.target = entity
            for j, name in enumerate combat.entityToCombat[entity].systems.keys:
              if j == targ.targetSelection:
                targ.weaponSystem.targetSystem = name
                break

        reset targ.selecting


  if Draw in flags:
    case targ.selecting:
    of WeaponSelect:
      var weapons: seq[WeaponDialog]

      for name, system in theState.systems.pairs:
        if Targetable in system.realSystem.flags:
          weapons.add WeaponDialog(
            name: name.string,
            damage: system.realSystem.damageDealt,
            chargeTurns: system.realSystem.chargeTurns,
            chargeCost: system.realSystem.chargeEnergyCost,
            activateCost: system.realSystem.activateCost,
            target:
              if system.target != nil:
                gameState.world.getEntity(system.target).name & " - " & system.targetSystem
              else:
                ""
          )

      gameState.buffer.printPaged(
        weapons,
        targ.weaponSelection,
        unselectedModifier = (proc(props: var GlyphProperties) =
          props.foreground = props.foreground * 0.3f
        ),
        tickerProgress = targ.tickerProgress
        )

    else:
      let combat = gameState.activeCombat()
      for i, entity in enumerate targ.weaponSystem.targetableEntities(combat, gameState.activeShip):
        if i == targ.entitySelection:
          gameState.buffer.put("<")
          gamestate.buffer.put(gameState.world.getEntity(entity).name.string.center(gameState.buffer.lineWidth - 2))
          gameState.buffer.put(">")
          gameState.buffer.newLine()
          gameState.buffer.put(" ")

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
          gameState.buffer.put ("-".repeat(gameState.buffer.lineWidth))
          gameState.buffer.newLine()


          var targetEntries: seq[TargetDialog]
          for name, system in combat.entityToCombat[entity].systems.pairs:
            targetEntries.add TargetDialog(
              name: name.string,
              damageModifier: system.realSystem.damageModifier,
              health: (system.realSystem.currentHealth, system.realSystem.maxHealth)
            )

          gameState.buffer.printPaged(
            targetEntries,
            targ.targetSelection,
            unselectedModifier = (proc(props: var GlyphProperties) =
              props.foreground = props.foreground * 0.3f
            ),
            tickerProgress = targ.tickerProgress
          )


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

    let system = state.systems[systemName]
    case (let fireState = state.systems[systemName].fireState(); fireState)
    of NoTarget:
      gameState.writeError($fireState)
    of InsufficientlyCharged:
      gameState.writeError($fireState % $system.turnsTillCharged())
    of None:
      {.warning: "Print out the target we're targetting".}
      let fireError = state.fire(systemName)
      if fireError != None:
        gameState.writeError($fireError % system.realSystem.name)
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
  gameState.activeCombat.endTurn(gameState.world)

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
      if error != None:
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


proc onExit(_: var Action, gameState: var GameState) = discard

type ActionEntry = object
  action: ActionKind
  name: string
  cost: int



proc update(_: var Action, gameState: var GameState, truss: var Truss, dt: float32, flags: ProgramFlags) =
  if Draw in flags:
    var actions: seq[ActionEntry]
    for action in gameState.activeCombatState().actions:
      actions.add ActionEntry(
        action: action.kind,
        name: action.system.realSystem.name.string,
        cost: action.cost
      )
    gameState.buffer.printPaged(actions)

proc name(_: Action): string = "action"
proc getFlags(_: Action): set[ProgramFlag] = {}

proc handler(_: Action, gameState: var GameState, input: string) =
  gameState.enterProgram(Action().toTrait(Program))

proc suggest(_: Action, gameState: GameState, input: string, ind: var int): string =
  ""

proc help(_: Action): string = "Shows all the present actions"
proc manual(_: Action): string = ""
storeCommand Action().toTrait(CommandImpl), {InCombat}
