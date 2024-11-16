import "$projectdir"/screenutils/screenrenderer
import "$projectdir"/screenutils/[styledtexts, texttables, progressbars]
import "$projectdir"/data/useroptions
import std/[enumerate, macros, strutils, typetraits]
import pkg/[truss3D, chroma]
import gamestates

type
  Interaction* = enum
    Decrement
    Increment
    Enter
    Exit

proc handleInput[T: range; Y](val: var T, increment: Y, interaction: set[Interaction]) =
  var newVal = rangeBase(T)(val)
  if Decrement in interaction:
    newVal -= increment
    if newVal > val:
      newVal = val
  elif Increment in interaction:
    newVal += increment
    if newVal < val:
      newVal = val

  newVal = clamp(newVal, T.low, T.high)

  val = newVal

proc inspector(name: sink StyledText, val: range[0f..1f], width, lineWidth: int, gameState: GameState): StyledText =
  result = name
  result.add " "
  result.add val.formatFloat(precision = 2)
  result = result.alignLeft(lineWidth - width - 2)

  result.add progressbar(val.float32, width, gradient = [(gameState.buffer.properties, 0f)])

proc inspector[T: range](name: sink StyledText, val: T, width, lineWidth: int, gameState: GameState): StyledText =
  result = name
  result.add " "
  result.add $val
  result = result.alignLeft(lineWidth - width - 2)

  result.add progressbar(
    (val - T.low).float32 / T.high.float32,
    width,
    gradient = [(gameState.buffer.properties, 0f)]
  )


proc onExit(_: var UserOptions; gameState: var GameState) {.nimcall, nimcall.} = discard

proc update(opt: var UserOptions, gameState: var GameState, truss: var Truss, dt: float32, flags: ProgramFlags) =

  var interact: set[Interaction]

  if TakeInput in flags:
    if truss.inputs.isDownRepeating(KeyCodeDown):
      inc opt.selected

    if truss.inputs.isDownRepeating(KeyCodeUp):
      dec opt.selected


    if truss.inputs.isDownRepeating(KeyCodeLeft):
      interact.incl Decrement

    if truss.inputs.isDownRepeating(KeyCodeRight):
      interact.incl Increment

  if Draw in flags:
    var i = 0
    for fieldName, field in gameState.options.fieldPairs:
      when fieldName != "selected":
        let isSelected = i == opt.selected

        if isSelected:
          let incVal =
            when field.hasCustomPragma(increment):
              field.getCustomPragmaVal(increment)[0]
            else:
              typeof(field) 1

          field.handleInput(incVal, interact)


        when field.hasCustomPragma(title):
          gameState.buffer.put field.getCustomPragmaVal(title).center(gameState.buffer.lineWidth)
          gameState.buffer.newLine()


        let name =
          when field.hasCustomPragma(useroptions.name):
            field.getCustomPragmaVal(useroptions.name)
          else:
            fieldName.styledText()
        gameState.buffer.put(
          inspector(name, field, 15, gameState.buffer.lineWidth, gameState),
          modifier =
            if not isSelected:
              proc(props: var GlyphProperties) = props.foreground = props.foreground - 0.4
            else:
              nil
        )
        gameState.buffer.newLine()
        inc i
    opt.selected = clamp(opt.selected, 0, i - 1)


proc name(_: UserOptions): string = "options"
proc getFlags(_: UserOptions): set[ProgramFlag] = {}

proc handler(_: UserOptions, gameState: var GameState, input: string) =
  gameState.enterProgram(UserOptions().toTrait(Program))

proc suggest(_: UserOptions, gameState: GameState, input: string, ind: var int): string =
  ""

proc help(_: UserOptions): string = "Shows all the present actions"
proc manual(_: UserOptions): string = ""
storeCommand UserOptions().toTrait(CommandImpl)
