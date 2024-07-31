import std/[times, os]
import screenutils/screenrenderer
import programs/[gamestates]
import pkg/[vmath, pixie, truss3D]
import pkg/truss3D/[inputs, logging]

var
  gameState: GameState
  coverTex: Texture
  screenShader: Shader
  rectModel: Model
  time: float32
  shaderModificationTime: Time

proc init =
  gameState = GameState.init()
  coverTex = genTexture()

  var modelData: MeshData[Vec2]
  modelData.appendVerts [vec2(0, 0), vec2(0, 1), vec2(1, 1), vec2(1, 0)].items
  modelData.append [0u32, 1, 2, 0, 2, 3].items
  modelData.appendUv [vec2(0, 0), vec2(0, 1), vec2(1, 1), vec2(1, 0)].items

  rectModel = uploadData(modelData)

  readImage("console.png").copyTo coverTex
  screenShader = loadShader(ShaderPath"vert.glsl", ShaderPath"screen.frag.glsl")
  shaderModificationTime = max(getLastModificationTime("vert.glsl"), getLastModificationTime("screen.frag.glsl"))


proc draw() =
  for i, screen in gameState.screenPairs:

    screen.buffer.render()

    let
      scrSize = screenSize().vec2
      scale = min(scrSize.x / gameState.screenWidth.float32, scrSize.y / gameState.screenHeight.float32)
      sizeX = (scale * screen.buffer.lineWidth.float32)
      sizeY = (scale * screen.buffer.lineHeight.float32)
      size = vec2(sizeX, sizeY) / scrSize * 2 # times 2 cause the rect is only 0..1 but Opengl is -1..1
      offset = abs(vec2(scale * gameState.screenWidth.float32, scale * gameState.screenHeight.float32) - scrSize) / scrSize

    var pos = vec3(screen.x.float32 * scale, screen.y.float32 * scale, 1) / vec3(scrSize, 1)
    pos.y *= -1
    pos.xy = pos.xy * 2f + vec2(-1f + offset.x, 1f - size.y - offset.y)

    let mat = translate(pos) * scale(vec3(size, 0))

    if screenShader.Gluint > 0:
      with screenShader:
        screenShader.setUniform("tex", screen.buffer.getFrameBufferTexture(), required = false)
        screenShader.setUniform("mvp", mat, required = false)
        screenShader.setUniform("fontHeight", screen.buffer.fontSize, required = false)
        screenShader.setUniform("time", time, required = false)
        screenShader.setUniform("screenSize", scrSize, required = false)
        #screenShader.setUniform("curve", gameState.curveAmount)
        screenShader.setUniform("activeScreen", float32(i == gameState.currentScreen))
        render(rectModel)



when not defined(testing):
  proc update(dt: float32) =
    gamestate.update(dt)
    time += dt

    let currModTime = max(getLastModificationTime("vert.glsl"), getLastModificationTime("screen.frag.glsl"))
    if shaderModificationTime < currModTime:
      screenShader = loadShader(ShaderPath"vert.glsl", ShaderPath"screen.frag.glsl")
      shaderModificationTime = currModTime
else:
  import screenutils/pam
  import pkg/pixie/fileformats/png


  var errorCode: int
  template genTest(name: string, dt: float32, body: untyped) =
    body
    gameState.buffer.upload(dt)
    gameState.buffer.render()

    var img = newImage(gameState.buffer.pixelWidth, gameState.buffer.pixelHeight)

    glGetTextureImage(gameState.buffer.getFrameBufferTexture().Gluint, 0, GlRgba,  GlUnsignedByte, img.data.len * 4, img.data[0].addr)
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

  proc update(dt: float32) =
    genTest("console/welcomescreen", 0):
      gameState.update(0)

    genTest("console/username", 0):
      inputs.inputs.inputText() = "t"
      gameState.update(0.1)
      inputs.inputs.inputText() = ""
      gameState.update(0.1)

    genTest("console/loggedin", 0):
      inputs.inputs.simulateDownRepeating(KeyCodeReturn)
      gameState.update(0)
      inputs.inputs.simulateClear(KeyCodeReturn)

    genTest("console/sensors", 0):
      inputs.inputs.inputText() = "sensors"
      gameState.update(0.1)
      inputs.inputs.inputText() = ""
      inputs.inputs.simulateDownRepeating(KeyCodeReturn)
      gameState.update(0.1)
      inputs.inputs.simulateClear(KeyCodeReturn)

    genTest("console/exitprogram", 0):
      inputs.inputs.simulateDown(KeyCodeEscape)
      gameState.update(0.1)
      inputs.inputs.simulateClear(KeyCodeEscape)

    genTest("console/scrollUp", 0):
      inputs.inputs.simulateDownRepeating(KeycodePageUp)
      gameState.update(0.1)
      inputs.inputs.simulateClear(KeycodePageUp)

    genTest("console/scrollDown", 0):
      inputs.inputs.simulateDownRepeating(KeycodePageDown)
      gameState.update(0.1)
      gameState.update(0.1)
      inputs.inputs.simulateClear(KeycodePageDown)

    quit errorCode

addLoggers("keyboardwarrior")
initTruss("Something", ivec2(1280, 720), keyboardwarrior.init, keyboardwarrior.update, draw, vsync = true)
