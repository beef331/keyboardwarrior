import std/[strscans, strutils]
import gamestates
import ../screenrenderer

var validNames {.compileTime.}: seq[string]
proc handleTextChange(gamestate: var GameState, input: string) =
  var toSetField, val: string
  if input.scanf("$s$w$s$+", toSetField, val):
    var foundName = false
    case toSetField
    of "size":
      static: validNames.add "size"
      foundName = true
      try:
        let newSize = parseInt(val)
        if newSize notin 5..maxTextSize:
          raise (ref ValueError)(msg: "Expected value in $#, but got: $#" % [$(5..maxTextSize), $newSize])
        gamestate.buffer.setFontSize(newSize)
      except CatchableError as e:
        gamestate.writeError(e.msg & "\n")
    of "width", "height":
      static: validNames.add "size"
      foundName = true
      try:
        let newSize = parseInt(val)
        if newSize notin 30..80:
          raise (ref ValueError)(msg: "Expected value in $#, but got: $#" % [$(30..80), $newSize])
        if toSetField[0] == 'h':
          gamestate.buffer.setLineHeight(newSize)
        else:
          gamestate.buffer.setLineWidth(newSize)
      except CatchableError as e:
        gamestate.writeError(e.msg & "\n")
    of "font":
      static: validNames.add "font"
      foundName = true
      try:
        let size = gamestate.buffer.fontSize
        gamestate.buffer.setFont(readFont(val & ".ttf"))
        gamestate.buffer.setFontSize(size)
      except CatchableError as e:
        gamestate.writeError(e.msg & "\n")

    else:
      for name, field in gamestate.buffer.properties.fieldPairs:
        static: validNames.add name
        if name.cmpIgnoreStyle(toSetField) == 0:
          foundName = true
          try:
            when field is SomeFloat:
              field = parseFloat(val)
            elif field is Color:
              field = parseHtmlColor(val)
            gamestate.buffer.put ($gamestate.buffer.properties).replace(",", ",\n") & "\n"
          except CatchableError as e:
            gamestate.writeError(e.msg & "\n")
    if not foundName:
      gamestate.writeError("No property named `$#`\nValid property names are:\n$#\n" % [toSetField, static(validNames.join("\n"))])
  else:
    gamestate.writeError("Incorrect command expected `text propertyName value`\n")

command(
  "text",
  "This command allows you to change the properties of the terminal text",
  handleTextChange
)
