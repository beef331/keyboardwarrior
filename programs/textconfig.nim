{.used.}
import std/[strscans, strutils]
import gamestates
import ../screenutils/screenrenderer

type TextCommand = object

var validNames {.compileTime.}: seq[string]
proc handler(_: TextCommand, gamestate: var GameState, input: string) =
  var toSetField, val: string
  if input.scanf("$s$w$s$+", toSetField, val):
    var foundName = false
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
          gamestate.writeError(e.msg)
    if not foundName:
      gamestate.writeError("No property named `$#`\nValid property names are:\n$#" % [toSetField, static(validNames.join("\n"))])
  else:
    gamestate.writeError("Incorrect command expected `text propertyName value`")

proc suggest(_: TextCommand, gameState: GameState, input: string, ind: var int): string =
  const names = static(validNames)
  case input.suggestIndex()
  of 0, 1:
    suggestNext(names.items, input, ind)
  else:
    ""

const manualText = """
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

proc name(_: TextCommand): string = "text"
proc help(_: TextCommand): string = "This command allows you to change the properties of the terminal text"
proc manual(_: TextCommand): string = manualText

storeCommand TextCommand().toTrait(CommandImpl)

