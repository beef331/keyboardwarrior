import std/[strutils, strscans, tables, xmltree, htmlparser, hashes, algorithm, random]
import std/private/asciitables
import screenrenderer, texttables, hardwarehacksuite
import pkg/truss3D/[inputs, models]
import pkg/[vmath, pixie, truss3D]

const maxTextSize = 50

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
    buffer.put(node.text.replace("\n"), props)
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

type Program = enum
  Nothing
  Sensors
  Hacking

var
  buffer = Buffer(lineWidth: 40, lineHeight: 30, properties: GlyphProperties(foreground: parseHtmlColor("White")))
  fontPath = "PublicPixel.ttf"
  input = ""
  commands = initTable[InsensitiveString, CommandHandler]()
  screenModel, coverModel: Model
  coverTex: Texture
  screenShader, coverShader: Shader
  currentProgram = Program.Nothing
  programX, programY: int

var validNames {.compileTime.}: seq[string]
proc handleTextChange(buff: var Buffer, input: string) =
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
        buff.setFontSize(newSize)
      except CatchableError as e:
        buffer.put(e.msg & "\n", GlyphProperties(foreground: red))
    of "font":
      static: validNames.add "font"
      foundName = true
      try:
        let size = buff.fontSize
        buff.setFont(readFont(val & ".ttf"))
        buff.setFontSize(size)
      except CatchableError as e:
        buffer.put(e.msg & "\n", GlyphProperties(foreground: red))

    else:
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
      buffer.put("No property named `$#`\nValid property names are:\n$#\n" % [toSetField, static(validNames.join("\n"))], GlyphProperties(foreground: red))
  else:
    buffer.put("Incorrect command expected `text propertyName value`\n", GlyphProperties(foreground: red))

proc enterProgram(program: Program) =
  currentProgram = program
  (programX, programY) = buffer.getPosition()
  buffer.toBottom()


var
  hack: HardwareHack
  cameraPos: Vec3 = vec3(0.15, -0.6, -0.8)

commands[insStr"toggle3d"] = proc(buffer: var Buffer, _: string) =
  buffer.toggleFrameBuffer()
commands[insStr"text"] = handleTextChange
commands[insStr"clear"] = proc(buffer: var Buffer, _: string) =
  buffer.toBottom()
commands[insStr"sensors"] = proc(buffer: var Buffer, _: string) =
  enterProgram(Sensors)


commands[insStr"event"] = proc(buffer: var Buffer, str: string) =
  var
    name = ""
    errored = false
  if str.scanf("$s$+", name):
    try:
      buffer.displayEvent(name & ".html")
    except:
      errored = true
  else:
    errored = true

  if errored:
    buffer.put("Failed to display event\n", GlyphProperties(foreground: red))

commands[insStr"hhs"] = proc(buffer: var Buffer, str: string) =
  if not hack.isInit:
    randomize()
    var password = newString(5)
    for ch in password.mitems:
      ch = sample(Digits + Letters)
    hack = HardwareHack.init(20, rand(0..10), "Orion", password, 3)
  enterProgram(Hacking)


commands[insStr"position"] = proc(buffer: var Buffer, str: string) =
  var x,y,z: float
  if str.len == 0:
    buffer.put cameraPos.x.formatFloat(precision = 2) & " " & cameraPos.y.formatFloat(precision = 2) & " " & cameraPos.z.formatFloat(precision = 2)
    buffer.newline()
  elif str.scanf("$s$f$s$f$s$f", x, y, z):
    cameraPos = vec3(x, y, z)

  else:
    buffer.put("Expected x y z\n", GlyphProperties(foreground: red))

proc init =
  buffer.initResources(fontPath, false)
  startTextInput(default(inputs.Rect), "")
  buffer.put(">")
  buffer.toggleFrameBuffer()

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

proc sensorUpdate(dt: float32) =
  var
    props: seq[GlyphProperties]
    nameProp = GlyphProperties(foreground: parseHtmlColor"Orange")
    yellow = GlyphProperties(foreground: parseHtmlColor"Yellow")
    red = GlyphProperties(foreground: parseHtmlColor"red")
  for entry in entries.mitems:
    entry.distance -= entry.speed * dt
    if entry.faction == "Alliance":
      props.add red
    else:
      props.add nameProp
    props.add buffer.properties
    props.add buffer.properties
    if entry.faction == "Alliance":
      props.add red
    else:
      props.add yellow

  entries = entries.sortedByIt(it.distance)
  buffer.printTable(entries, entryProperties = props, formatProperties = TableFormatProps(floatSigDigs: 4))


proc update(dt: float32) =
  if hack.isInit:
    hack.update(dt, currentProgram == Hacking)

  case currentProgram
  of Nothing:
    if isTextInputActive():
      if inputText().len > 0:
        input.add inputText()
        buffer.clearLine()
        buffer.put(">" & input)
      if KeyCodeReturn.isDownRepeating():
        buffer.newLine()
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
    buffer.clearTo(programY)
    buffer.cameraPos = programY
    case range[succ(Nothing)..Program.high](currentProgram)
    of Sensors:
      sensorUpdate(dt)
    of Hacking:
      buffer.put hack

  if currentProgram != Nothing and KeyCodeEscape.isDown:
    currentProgram = Nothing
    buffer.put ">"

  buffer.upload(dt)
  setInputText("")

proc draw =
  var
    projMatrix = perspective(50f, screenSize().x / screenSize().y, 0.1, 50)
    viewMatrix = (vec3(0, 0, -1).toAngles(vec3(0)).fromAngles())

  buffer.render()
  if buffer.usingFrameBuffer:
    glEnable(GlDepthTest)
    with coverShader:
      coverShader.setUniform("tex", coverTex)
      coverShader.setUniform("mvp", projMatrix * viewMatrix * (mat4() * translate(vec3(cameraPos))))
      render(coverModel)

    with screenShader:
      screenShader.setUniform("tex", buffer.getFrameBufferTexture())
      screenShader.setUniform("mvp", projMatrix * viewMatrix * (mat4() * translate(cameraPos)))
      render(screenModel)

initTruss("Something", ivec2(1280, 720), init, update, draw, vsync = true)
