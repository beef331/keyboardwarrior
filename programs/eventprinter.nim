{.used.}
import gamestates
import std/[strutils, xmltree, htmlparser, strscans]

proc printTree(buffer: var Buffer, node: XmlNode, props: var GlyphProperties) =
  let oldProp = props
  if node.kind == xnElement:
    if node.tag == "br":
      buffer.put "\n", props
    else:
      for name, field in props.fieldPairs:
        let val = node.attr(name.toLowerAscii())
        if val != "":
          when field is SomeFloat:
            field = parseFloat(val)
          elif field is Color:
            field = parseHtmlColor(val)
      for child in node:
        buffer.printTree(child, props)
  else:
    buffer.put(node.text.multiReplace({"\n": "", "  ": ""}), props)
  props = oldProp

proc displayEvent*(buffer: var Buffer, event: string, isPath = true) =
  let xml =
    if isPath:
      readFile(event).parseHtml()
    else:
      if event.len == 0: return
      event.parseHtml()
  if xml.len == 0:
    return

  var props = buffer.properties
  for name, field in props.fieldPairs:
    let val = xml[0].attr(name.toLowerAscii())
    if val != "":
      when field is SomeFloat:
        field = parseFloat(val)
      elif field is Color:
        field = parseHtmlColor(val)
  buffer.printTree(xml[0], props)

proc eventHandler(gameState: var GameState, str: string) =
  var
    name = ""
    errored = false
  if str.scanf("$s$+", name):
    try:
      gameState.buffer.displayEvent(name & ".html")
    except:
      errored = true
  else:
    errored = true

  if errored:
    gameState.writeError("Failed to display event\n")


command(
  "event",
  "A debug command that shows events",
  eventHandler
)
