import std/[times, os]
import screenutils/screenrenderer
import programs/[gamestates]
import pkg/[vmath, pixie, truss3D]
import pkg/truss3D/[inputs, logging]

import pkg/potato

var
  gameState {.persistent.}: GameState
  screenShader {.persistent.}: Shader
  rectModel {.persistent.}: Model
  shaderModificationTime {.persistent.}: Time

proc init(truss: var Truss) =
  gameState = GameState.init()

  var modelData: MeshData[Vec2]
  modelData.appendVerts [vec2(0, 0), vec2(0, 1), vec2(1, 1), vec2(1, 0)].items
  modelData.append [0u32, 1, 2, 0, 2, 3].items
  modelData.appendUv [vec2(0, 0), vec2(0, 1), vec2(1, 1), vec2(1, 0)].items

  rectModel = uploadData(modelData)

  screenShader = loadShader(ShaderPath"vert.glsl", ShaderPath"screen.frag.glsl")
  shaderModificationTime = max(getLastModificationTime("vert.glsl"), getLastModificationTime("screen.frag.glsl"))


proc draw(truss: var Truss) =
  for screen in gameState.screens:

    screen.buffer.render()

    let
      scrSize = truss.windowSize.vec2
      scale = min(scrSize.x / gameState.screenWidth.float32, scrSize.y / gameState.screenHeight.float32)
      sizeX = (scale * screen.w)
      sizeY = (scale * screen.h)
      size = vec2(sizeX, sizeY) / scrSize * 2 # times 2 cause the rect is only 0..1 but Opengl is -1..1
      offset = abs(vec2(scale * gameState.screenWidth.float32, scale * gameState.screenHeight.float32) - scrSize) / scrSize

    var pos = vec3(screen.x * scale, screen.y * scale, 1) / vec3(scrSize, 1)
    pos.y *= -1
    pos.xy = pos.xy * 2f + vec2(-1f + offset.x, 1f - size.y - offset.y)

    let mat = translate(pos) * scale(vec3(size, 0))

    if screenShader.Gluint > 0:
      with screenShader:
        screenShader.setUniform("tex", screen.buffer.getFrameBufferTexture(), required = false)
        screenShader.setUniform("mvp", mat, required = false)
        screenShader.setUniform("fontHeight", screen.buffer.fontSize, required = false)
        screenShader.setUniform("time", truss.time, required = false)
        screenShader.setUniform("screenSize", scrSize, required = false)
        #screenShader.setUniform("curve", gameState.curveAmount)
        screenShader.setUniform("activeScreen", float32(screen == gameState.screen))
        render(rectModel)



when not defined(testing):
  proc update(truss: var Truss, dt: float32) =
    gamestate.update(truss,dt)

    let currModTime = max(getLastModificationTime("vert.glsl"), getLastModificationTime("screen.frag.glsl"))
    if shaderModificationTime < currModTime:
      screenShader = loadShader(ShaderPath"vert.glsl", ShaderPath"screen.frag.glsl")
      shaderModificationTime = currModTime
else:
  import screenutils/pam
  import pkg/pixie/fileformats/png
  import pkg/opengl


  var errorCode: int
  template genTest(name: string, dt: float32, body: untyped) =
    glClear(GlColorBufferBit)
    body
    draw(truss)
    var img = newImage(truss.windowSize.x, truss.windowSize.y)

    glReadPixels(0, 0, img.width, img.height, GlRgba,  GlUnsignedByte, img.data[0].addr)
    img.flipVertical()
    let
      path = "tests" / "testimages" / name.changeFileExt("png")
      testPath = path.changeFileExt("test.png")
      debugPath = path.changeFileExt("debug.png")
    if not fileExists(path):
      img.writeFile(path)
    else:
      if not compare(ImageComparison(data: path, isPath: true), ImageComparison(data: img.encodePng()), 0.0001, debugPath):
        img.writeFile(testPath)
        echo "Error: Failed to match ", name
        errorCode = 1

  proc update(truss: var Truss, dt: float32) =
    genTest("console/welcomescreen", 0):
      gameState.update(truss, 0)

    genTest("console/username", 0):
      truss.inputs.inputText() = "t"
      gameState.update(truss, 0.0)
      truss.inputs.inputText() = ""
      gameState.update(truss, 0.0)

    genTest("console/loggedin", 0):
      truss.inputs.simulateDownRepeating(KeyCodeReturn)
      gameState.update(truss, 0)
      truss.inputs.simulateClear(KeyCodeReturn)

    genTest("console/sensors", 0):
      truss.inputs.inputText() = "sensors"
      gameState.update(truss, 0.0)
      truss.inputs.inputText() = ""
      truss.inputs.simulateDownRepeating(KeyCodeReturn)
      gameState.update(truss, 0.0)
      truss.inputs.simulateClear(KeyCodeReturn)

    genTest("console/exitprogram", 0):
      truss.inputs.simulateDown(KeyCodeEscape)
      gameState.update(truss, 0.0)
      truss.inputs.simulateClear(KeyCodeEscape)

    genTest("console/scrollUp", 0):
      truss.inputs.simulateDownRepeating(KeycodePageUp)
      gameState.update(truss, 0.0)
      truss.inputs.simulateClear(KeycodePageUp)

    genTest("console/scrollDown", 0):
      truss.inputs.simulateDownRepeating(KeycodePageDown)
      gameState.update(truss, 0.0)
      gameState.update(truss, 0.0)
      truss.inputs.simulateClear(KeycodePageDown)

    genTest("console/splitv", 0):
      truss.inputs.inputText() = "splitv"
      gameState.update(truss, 0.0)
      truss.inputs.simulateDownRepeating(KeyCodeReturn)
      gameState.update(truss, 0.0)
      truss.inputs.simulateClear(KeyCodeReturn)

    genTest("console/splith", 0):
      truss.inputs.inputText() = "splith"
      gameState.update(truss, 0.0)
      truss.inputs.simulateDownRepeating(KeyCodeReturn)
      gameState.update(truss, 0.0)
      truss.inputs.simulateClear(KeyCodeReturn)

    genTest("console/navigateright", 0):
      truss.inputs.simulatePressed(KeyCodeLAlt)
      truss.inputs.simulateDownRepeating(KeyCodeRight)
      gameState.update(truss, 0.0)
      truss.inputs.simulateClear(KeyCodeLAlt)
      truss.inputs.simulateClear(KeyCodeRight)
      gameState.update(truss, 0.0)

    genTest("console/navigateleft", 0):
      truss.inputs.simulatePressed(KeyCodeLAlt)
      truss.inputs.simulateDownRepeating(KeyCodeLeft)
      gameState.update(truss, 0.0)
      truss.inputs.simulateClear(KeyCodeLAlt)
      truss.inputs.simulateClear(KeyCodeLeft)
      gameState.update(truss, 0.0)

    genTest("console/navigatedown", 0):
      truss.inputs.simulatePressed(KeyCodeLAlt)
      truss.inputs.simulateDownRepeating(KeyCodeDown)
      gameState.update(truss, 0.0)
      truss.inputs.simulateClear(KeyCodeLAlt)
      truss.inputs.simulateClear(KeyCodeDown)
      gameState.update(truss, 0.0)

    genTest("console/navigateup", 0):
      truss.inputs.simulatePressed(KeyCodeLAlt)
      truss.inputs.simulateDownRepeating(KeyCodeUp)
      gameState.update(truss, 0.0)
      truss.inputs.simulateClear(KeyCodeLAlt)
      truss.inputs.simulateClear(KeyCodeUp)
      gameState.update(truss, 0.0)

    quit errorCode

addLoggers("keyboardwarrior")
const flags =
  when defined(testing):
    {}
  else:
    {Resizable}
var truss {.persistent.} = Truss.init("Keyboard Warrior", ivec2(1280, 720), keyboardwarrior.init, keyboardwarrior.update, draw, flags = flags, vsync = true)

proc potatoMain() {.exportc, dynlib.} =
  truss.update()
  if truss.inputs.isDown(KeyCodeF11):
    potatoCompileIt()

  echo "hello"
