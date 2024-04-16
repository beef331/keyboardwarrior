import std/[strutils, strscans, tables, xmltree, htmlparser, hashes, algorithm]
import std/private/asciitables
import screenrenderer
import pkg/truss3D/[inputs, models]
import pkg/[vmath, pixie, truss3D]

type
  InsensitiveString = distinct string
  CommandHandler = proc(buffer: var Buffer, input: string) {.nimcall.}

converter toString(str: InsensitiveString): lent string = string(str)
converter toString(str: var InsensitiveString): var string = string(str)

proc `==`(a, b: InsensitiveString): bool =
  cmpIgnoreStyle(a, b) == 0

proc hash(str: InsensitiveString): Hash =
  for ch in str.items:
    let ch = ch.toLowerAscii()
    if ch != '_':
      result = result !& hash(ch)

  result = !$result

proc insStr(s: sink string): InsensitiveString = InsensitiveString(s)

proc printTree(buffer: var Buffer, node: XmlNode, props: var GlyphProperties) =
  let oldProp = props
  if node.kind == xnElement:
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
    buffer.put(node.text, props)
  props = oldProp


proc displayEvent(buffer: var Buffer, eventPath: string) =
  let xml = readFile(eventPath).parseHtml()
  var props = buffer.properties
  for name, field in props.fieldPairs:
    let val = xml[0].attr(name.toLowerAscii())
    if val != "":
      when field is SomeFloat:
        field = parseFloat(val)
      elif field is Color:
        field = parseHtmlColor(val)
  buffer.printTree(xml[0], props)

const red = parseHtmlColor("Red")

var
  buffer = Buffer(pixelWidth: 480, pixelHeight: 320, properties: GlyphProperties(foreground: parseHtmlColor("White")))
  fontPath = "PublicPixel.ttf"
  input = ""
  commands = initTable[InsensitiveString, CommandHandler]()
  screenModel, coverModel: Model
  coverTex: Texture
  screenShader, coverShader: Shader
  inDummyProgram: bool
  dummyX, dummyY: int

var validNames {.compileTime.}: seq[string]
proc handleTextChange(buff: var Buffer, input: string) =
  var toSetField, val: string
  if input.scanf("$s$w$s$w", toSetField, val):
    var foundName = false
    for name, field in buff.properties.fieldPairs:
      static: validNames.add name
      if name.cmpIgnoreStyle(toSetField) == 0:
        foundName = true
        try:
          when field is SomeFloat:
            field = parseFloat(val)
          elif field is Color:
            field = parseHtmlColor(val)
          buffer.put ($buffer.properties).replace(",", ",\n") & "\n"
        except CatchableError as e:
          buffer.put(e.msg & "\n", GlyphProperties(foreground: red))
    if not foundName:
      buffer.put("No property named `$#`\nValid property names are:\n$#\n" % [toSetField, static(validNames).join("\n")], GlyphProperties(foreground: red))
  else:
    buffer.put("Incorrect command expected `text propertyName value`\n", GlyphProperties(foreground: red))


commands[insStr"toggle3d"] = proc(buffer: var Buffer, _: string) =
  buffer.toggleFrameBuffer()
commands[insStr"text"] = handleTextChange
commands[insStr"clear"] = proc(buffer: var Buffer, _: string) =
  buffer.toBottom()
commands[insStr"sensors"] = proc(buffer: var Buffer, _: string) =
  inDummyProgram = true
  (dummyX, dummyY) = buffer.getPosition()
  buffer.toBottom()


proc init =
  buffer.initResources(fontPath, false)
  buffer.displayEvent("event.html")
  startTextInput(default(inputs.Rect), "")
  buffer.put(">")

  screenModel = loadModel("consolescreen.glb")
  coverModel = loadModel("console.glb")
  coverTex = genTexture()


  readImage("console.png").copyTo coverTex

  coverShader = loadShader(ShaderPath"vert.glsl", ShaderPath"frag.glsl")
  screenShader = loadShader(ShaderPath"vert.glsl", ShaderPath"screen.frag.glsl")

proc dispatchCommand(buffer: var Buffer, input: string) =
  if input.len > 0:
    let
      ind =
        if (let ind = input.find(' '); ind) != -1:
          ind - 1
        else:
          input.high
      command = insStr input[0..ind]
    if command in commands:
      commands[command](buffer, input[ind + 1 .. input.high])
    else:
      buffer.put("Incorrect command\n", GlyphProperties(foreground: red))

var entries: seq[tuple[name: string, distance, speed: float32, faction: string]] = @[
  ("Orion", 500, 10, "Alliance"),
  ("Prometheus", 600, 40, "Incarnate"),
  ("Sisyphus", 10000, 100.0, "Wanderers"),
  ("Icarus", 13000, 95, "Wanderers")
]

proc update(dt: float32) =
  if not inDummyProgram:
    if isTextInputActive():
      if inputText().len > 0:
        input.add inputText()
        buffer.clearLine()
        buffer.put(">" & input)
      if KeyCodeReturn.isDownRepeating():
        buffer.put "\n"
        dispatchCommand(buffer, input)
        input = ""
        buffer.put(">")
      if KeyCodeBackspace.isDownRepeating() and input.len > 0:
        input.setLen(input.high)
        buffer.clearLine()
        buffer.put(">" & input)

    if KeyCodeUp.isDownRepeating():
      buffer.scrollUp()

    if KeyCodeDown.isDownRepeating():
      buffer.scrollDown()
  else:
    buffer.clearTo(dummyY)
    buffer.cameraPos = dummyY

    var message = ""

    for name, _ in default(typeof(entries[0])).fieldPairs:
      message.add name.capitalizeAscii() & "\t"

    message.add "\n"
    entries.sort(proc(a, b: typeof(entries[0])): int = cmp(a.distance, b.distance))
    for entry in entries.mitems:
      entry.distance -= entry.speed * dt
      for field in entry.fields:
        message.add:
          when field is float32:
            field.formatFloat(precision = 4)
          else:
            $field
        message.add "\t"
      message.add "\n"

    buffer.put message.alignTable()
    if KeyCodeEscape.isDown:
      inDummyProgram = false
      buffer.put ">"

  buffer.upload(dt)
  setInputText("")

proc draw =
  var
    projMatrix = perspective(60f, screenSize().x / screenSize().y, 0.1, 50)
    viewMatrix = (vec3(0, 0, -1).toAngles(vec3(0)).fromAngles())

  buffer.render()
  if buffer.usingFrameBuffer:
    glEnable(GlDepthTest)
    with coverShader:
      coverShader.setUniform("mvp", projMatrix * viewMatrix * (mat4() * translate(vec3(0.3, -0.75, -1))))
      render(coverModel)

    with screenShader:
      screenShader.setUniform("tex", buffer.getFrameBufferTexture())
      screenShader.setUniform("mvp", projMatrix * viewMatrix * (mat4() * translate(vec3(0.3, -0.75, -1))))
      render(screenModel)

initTruss("Something", ivec2(buffer.pixelWidth, buffer.pixelHeight), init, update, draw, vsync = true)
