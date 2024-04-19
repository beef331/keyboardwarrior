import std/[strutils, strscans, tables, xmltree, htmlparser, hashes, algorithm, random]
import screenrenderer, texttables
import programs/[gamestates]
import pkg/truss3D/[inputs, models]
import pkg/[vmath, pixie, truss3D]

const maxTextSize = 50

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

var
  gameState: GameState
  screenModel, coverModel: Model
  coverTex: Texture
  screenShader, coverShader: Shader
  cameraPos: Vec3 = vec3(0.15, -0.6, -0.8)

proc init =
  gameState = GameState.init()
  screenModel = loadModel("consolescreen.glb")
  coverModel = loadModel("console.glb")
  coverTex = genTexture()


  readImage("console.png").copyTo coverTex

  coverShader = loadShader(ShaderPath"vert.glsl", ShaderPath"frag.glsl")
  screenShader = loadShader(ShaderPath"vert.glsl", ShaderPath"screen.frag.glsl")

proc update(dt: float32) =
  gamestate.update(dt)

proc draw =
  var
    projMatrix = perspective(50f, screenSize().x / screenSize().y, 0.1, 50)
    viewMatrix = (vec3(0, 0, -1).toAngles(vec3(0)).fromAngles())

  gamestate.buffer.render()
  if gamestate.buffer.usingFrameBuffer:
    glEnable(GlDepthTest)
    with coverShader:
      coverShader.setUniform("tex", coverTex)
      coverShader.setUniform("mvp", projMatrix * viewMatrix * (mat4() * translate(vec3(cameraPos))))
      render(coverModel)

    with screenShader:
      screenShader.setUniform("tex", gamestate.buffer.getFrameBufferTexture())
      screenShader.setUniform("mvp", projMatrix * viewMatrix * (mat4() * translate(cameraPos)))
      render(screenModel)

initTruss("Something", ivec2(1280, 720), keyboardwarrior.init, keyboardwarrior.update, draw, vsync = true)
