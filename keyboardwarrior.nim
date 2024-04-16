import std/[strutils, strscans]
type
  BayKind = enum
    Nothing
    Rocket
    Turret

  AmmoKind = enum
    Bullet
    Rail
    Nuclear

  EntityFlag = enum
    Powered
    Damaged
    Jammed

  EntityFlags = set[EntityFlag]

  Entity = object of RootObj
    name: string

  PoweredEntity = object of Entity
    flags: EntityFlags

  LimitedVal[T] = object
    min, max: T
    val: T

  Bay = object of PoweredEntity
    target: string
    case kind: BayKind
    of Turret, Rocket:
      ammo: LimitedVal[int]
      ammoKind: AmmoKind
    else:
      discard

  Thing = object of Entity
    volume: int

  Room = object of PoweredEntity
    position: int
    inventory: seq[Thing]

  DoorState = enum
    Closed
    Opened

  Door = object of PoweredEntity
    state: DoorState

  SystemKind = enum
    Networking
    AutoTargetting
    AutoLoader
    JamProtection
    Sensors


  ShipSystem = object of PoweredEntity
    case kind: SystemKind
    of Sensors:
      sensorRange: int
    else: discard


  Ship = object of Entity
    weaponBays: seq[Bay]
    rooms: seq[Room]
    door: seq[Door]
    systems: seq[ShipSystem]
    fuel: LimitedVal[int]

proc hasSystem(ship: Ship, kind: SystemKind): bool =
  for system in ship.systems:
    if system.kind == kind:
      return true


proc load(ship: var Ship, name: string, kind: AmmoKind) =
  for bay in ship.weaponBays.mitems:
    if bay.name == name:
      if bay.ammo.val == 0:
        ## load the ammo
      elif not ship.hasSystem(JamProtection):
        bay.flags.incl Jammed

proc unjam(ship: var Ship, name: string) =
  for bay in ship.weaponBays.mitems:
    if bay.name == name:
      bay.flags.excl Jammed


import screenrenderer
import pkg/truss3D/[inputs, models]
import pkg/[vmath, pixie, truss3D]

var
  buffer = Buffer(pixelWidth: 320, pixelHeight: 240, properties: GlyphProperties(foreground: parseHtmlColor("White")))
  fontPath = "PublicPixel.ttf"
  input = ""

const red = parseHtmlColor("Red")


import std/[xmltree, htmlparser, strutils]

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


var
  screenModel, coverModel: Model
  coverTex: Texture
  screenShader, coverShader: Shader


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


proc handleTextChange(buff: var Buffer, input: string): bool =
  result = input.startsWith "text "
  var toSetField, val: string
  if input.scanf("text $+ $+", toSetField, val):
    var foundName = false
    for name, field in buff.properties.fieldPairs:
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
      buffer.put("No property named `$#`\n" % toSetField, GlyphProperties(foreground: red))
  elif result:
    buffer.put("Incorrect command expected `text propertyName value`\n", GlyphProperties(foreground: red))

proc update(dt: float32) =
  if isTextInputActive():
    if inputText().len > 0:
      input.add inputText()
      buffer.clearLine()
      buffer.put(">" & input)
      setInputText("")
    if KeyCodeReturn.isDownRepeating():
      buffer.put "\n"
      if input == "toggle3D":
        buffer.toggleFrameBuffer()
      elif not handleTextChange(buffer, input):
        buffer.put("Incorrect command\n", GlyphProperties(foreground: red))
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

  buffer.upload(dt)

proc draw =
  var
    projMatrix = perspective(60f, screenSize().x / screenSize().y, 0.1, 50)
    viewMatrix = (vec3(0, 0, -1).toAngles(vec3(0)).fromAngles())

  buffer.render()
  if buffer.usingFrameBuffer:
    glEnable(GlDepthTest)
    with coverShader:
      coverShader.setUniform("mvp", projMatrix * viewMatrix * (mat4() * translate(vec3(0.3, -0.75, -1.3))))
      render(coverModel)

    with screenShader:
      screenShader.setUniform("tex", buffer.getFrameBufferTexture())
      screenShader.setUniform("mvp", projMatrix * viewMatrix * (mat4() * translate(vec3(0.3, -0.75, -1.3))))
      render(screenModel)

initTruss("Something", ivec2(buffer.pixelWidth, buffer.pixelHeight), init, update, draw, vsync = true)
