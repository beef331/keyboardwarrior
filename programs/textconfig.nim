import std/[strscans, strutils]
import gamestates
import ../screenutils/screenrenderer

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

proc doSuggest(s: string): bool =
  s.len > 1 and s.find(WhiteSpace, 0) == s.rfind(WhiteSpace)

proc textSuggest(gameState: GameState, input: string, ind: var int): string =
  if input.doSuggest:
    template spaceLess: untyped = input.toOpenArray(1, input.high)
    var foundInds = 0
    const names = static: validNames

    var totalNameCount = 0
    for name in names:
      if name.insensitiveStartsWith spaceless:
        inc totalNameCount

    for name in names:
      if name.insensitiveStartsWith spaceless:
        if foundInds == (ind + 1) mod totalNameCount:
          inc ind
          result = name[spaceless.len..^1]
          break
        inc foundInds





const manual = """
<event>
<body>
<p foreground = "#aaaaaa">`text propertyName value`</p>
<br/><br/>
Sets terminal properties.<br/>
It has a variety of commands ranging from line width <br/> to shaking.<br/>
<br/><br/>
<p foreground = "#aaaaaa">`text font fontName`</p><br/>
Sets the font to the given font name.<br/>
The font should be monospace for best results.<br/>
<br/><br/>
<p foreground = "#aaaaaa">`text size sizeOfFont`</p><br/>
Sets the rendered font to a size.<br/>
<br/><br/>
<p foreground = "#aaaaaa">`text width someSize`</p><br/>
Sets the terminal width.<br/>
<br/><br/>
<p foreground = "#aaaaaa">`text height someSize`</p><br/>
Sets the terminal height.<br/>
<br/><br/>
<p foreground = "#aaaaaa">`text foreground color`</p><br/>
Sets the terminal text color.<br/>
Can be any HTML color, including rgb hexadecimal<br/>
<br/><br/>

<p background = "#0a0a0a">`text background color`</p><br/>
Sets the terminal background color.<br/>
Can be any HTML color, including rgb hexadecimal<br/>
<br/><br/>

<p foreground = "#aaaaaa" sinestrength = "0.1" sinespeed = "4">`text sinestrength strength`</p><br/>
Sets the sine movement strength<br/>

<p foreground = "#aaaaaa" sinestrength = "0.2" sinespeed = "10">`text sinespeed speed`</p><br/>
Sets the sine movement speed<br/>

<p foreground = "#aaaaaa" shakestrength = "0.1" shakespeed = "1">`text shakestrength strength`</p><br/>
Sets the shake movement strength<br/>

<p foreground = "#aaaaaa" shakestrength = "0.1" shakespeed = "3">`text shakespeed speed`</p><br/>
Sets the shake movement speed<br/>

</body>
</event>
"""


command(
  "text",
  "This command allows you to change the properties of the terminal text",
  handleTextChange,
  manual,
  textSuggest
)

