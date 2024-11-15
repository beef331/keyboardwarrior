import std/[times, os, json]
import screenutils/[screenrenderer, watchedshaders]
import programs/[gamestates]
import pkg/[vmath, pixie, truss3D, traitor]
import pkg/truss3D/[inputs, logging, shaders, textures]
import pkg/potato

when appType == "lib":
  proc serialise*[T](val: var Traitor[T], root: JsonNode): JsonNode =
    result = newJObject()
    if val == nil:
      result.add("id", newJInt(-1))
    else:
      result.add("id", newJInt(val.typeId))
      val.unpackIt:
        result.add("data", it.data.serialise(root))

  proc deserialise*[T](val: var Traitor[T], state: var DeserialiseState, current: JsonNode) =
    let id = current["id"].getInt()
    if id >= 0:
      T.repackIt(id):
        var newVal: typeof(It().data)
        newVal.deserialise(state, current["data"])
        val = newVal.toTrait(T)



  proc serialise*(val: var (proc), root: JsonNode): JsonNode = nil
  proc deserialise*(val: var (proc), state: var DeserialiseState, current: JsonNode) = discard

  proc serialise*[T: Shader | Texture | Ssbo | Truss](val: var T, root: JsonNode): JsonNode =
    result = potato.serialise(val, root)
    `=wasMoved`(val)

  proc deserialise*(val: var Shader, state: var DeserialiseState, current: JsonNode) =
    potato.deserialise(val, state, current)

var
  gameState {.persistent.}: GameState
  screenShader {.persistent.}: WatchedShader
  postProcessShader {.persistent.}: WatchedShader
  tempBuffer {.persistent.}: FrameBuffer
  rectModel {.persistent.}: Model

proc init(truss: var Truss) =
  gameState = GameState.init()

  var modelData: MeshData[Vec2]
  modelData.appendVerts [vec2(0, 0), vec2(0, 1), vec2(1, 1), vec2(1, 0)].items
  modelData.append [0u32, 1, 2, 0, 2, 3].items
  modelData.appendUv [vec2(0, 0), vec2(0, 1), vec2(1, 1), vec2(1, 0)].items

  rectModel = uploadData(modelData)

  screenShader = loadWatchedShader("vert.glsl", "screen.frag.glsl")
  postProcessShader = loadWatchedShader("vert.glsl", "postprocess.frag.glsl")
  tempBuffer = genFrameBuffer(truss.windowSize, tfRgba, wrapMode = ClampedToBorder)


proc draw(truss: var Truss) =
  tempBuffer.clear()
  for screen in gameState.screens:
    screen.buffer.render()

    let
      scrSize = truss.windowSize.vec2
      runeWidth = gameState.buffer.runeSize.x
      runeHeight = gameState.buffer.runeSize.y
      scale = min(scrSize.x / (gameState.screenWidth.float32 * runeWidth), scrSize.y / (gameState.screenHeight.float32 * runeHeight))
      sizeX = (scale * screen.w * runeWidth)
      sizeY = (scale * screen.h * runeHeight)
      size = vec2(sizeX, sizeY) / scrSize * 2 # times 2 cause the rect is only 0..1 but Opengl is -1..1
      offset = abs(vec2(scale * gameState.screenWidth.float32 * runeWidth, scale * gameState.screenHeight.float32 * runeHeight) - scrSize) / scrSize

    var pos = vec3(screen.x * scale * runeWidth, screen.y * scale * runeHeight, 1) / vec3(scrSize, 1)
    pos.y *= -1
    pos.xy = pos.xy * 2f + vec2(-1f + offset.x, 1f - size.y - offset.y)

    let mat = translate(pos) * scale(vec3(size, 0))


    if screenShader.shader.Gluint > 0:
      with tempBuffer:
        with screenShader:
          setUniform("tex", screen.buffer.getFrameBufferTexture(), required = false)
          setUniform("mvp", mat, required = false)
          setUniform("fontHeight", screen.buffer.fontSize, required = false)
          setUniform("time", truss.time, required = false)
          setUniform("screenSize", scrSize, required = false)
          setUniform("activeScreen", float32(screen == gameState.screen))
          render(rectModel)

  with postProcessShader:
    setUniform("tex", tempBuffer.colourTexture, required = false)
    setUniform("mvp", mat4()  * scale(vec3(2)) * translate(vec3(-0.5)), required = false)
    setUniform("curve", gameState.options.curveAmount, required = false)
    render(rectModel)



when not defined(testing):
  var lastScreenSize: IVec2
  proc update(truss: var Truss, dt: float32) =
    if lastScreenSize != truss.windowSize:
      tempBuffer.resize(truss.windowSize)

    gamestate.update(truss,dt)
    screenShader.reloadIfNeeded()
    lastScreenSize = truss.windowSize
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

when defined(hotpotato):
  truss.updateProc = keyboardwarrior.update
  truss.drawProc = keyboardwarrior.draw
  gameState.recalculateScreens()

  proc potatoMain() {.exportc, dynlib.} =
    if truss.updateProc != nil:
      truss.update()
    if truss.inputs.isDown(KeyCodeF11):
      potatoCompileIt()

    if truss.hasInit and not truss.isRunning:
      potatoQuit()
else:
  while truss.isRunning:
    truss.update()
