import std/[strutils, strscans, tables, xmltree, htmlparser, hashes, algorithm, random, times, os]
import screenutils/screenrenderer
import programs/[gamestates]
import pkg/truss3D/[inputs, models]
import pkg/[vmath, pixie, truss3D]

var
  gameState: GameState
  screenModel, coverModel: Model
  coverTex: Texture
  screenShader, coverShader: Shader
  cameraPos: Vec3 = vec3(0.15, -0.6, -0.8)
  rectModel: Model
  time: float32
  shaderModificationTime: Time


proc init =
  gameState = GameState.init()
  screenModel = loadModel("consolescreen.glb")
  coverModel = loadModel("console.glb")
  coverTex = genTexture()

  var modelData: MeshData[Vec2]
  modelData.appendVerts [vec2(0, 0), vec2(0, 1), vec2(1, 1), vec2(1, 0)].items
  modelData.append [0u32, 1, 2, 0, 2, 3].items
  modelData.appendUv [vec2(0, 0), vec2(0, 1), vec2(1, 1), vec2(1, 0)].items

  rectModel = uploadData(modelData)

  readImage("console.png").copyTo coverTex
  screenShader = loadShader(ShaderPath"vert.glsl", ShaderPath"screen.frag.glsl")
  shaderModificationTime = max(getLastModificationTime("vert.glsl"), getLastModificationTime("screen.frag.glsl"))

proc update(dt: float32) =
  gamestate.update(dt)
  time += dt

  let currModTime = max(getLastModificationTime("vert.glsl"), getLastModificationTime("screen.frag.glsl"))
  if shaderModificationTime < currModTime:
    screenShader = loadShader(ShaderPath"vert.glsl", ShaderPath"screen.frag.glsl")
    shaderModificationTime = currModTime


proc draw() =
  gamestate.buffer.render()
  let
    scrSize = screenSize().vec2
    scale = min(scrSize.x / gameState.buffer.lineWidth.float32, scrSize.y / gameState.buffer.lineHeight.float32)
    sizeX = (scale * gameState.buffer.lineWidth.float32)
    sizeY = (scale * gameState.buffer.lineHeight.float32)
    size = vec2(sizeX, sizeY) * 2 / scrSize

  var pos = vec3((scrSize.x - sizeX) / 2, (scrSize.y - sizeY) / 2, 1) / vec3(scrSize, 1)
  pos.y *= -1
  pos.xy = pos.xy * 2f + vec2(-1f, 1f - size.y)

  let mat = translate(pos) * scale(vec3(size, 0))

  if screenShader.Gluint > 0:
    with screenShader:
      screenShader.setUniform("tex", gamestate.buffer.getFrameBufferTexture(), required = false)
      screenShader.setUniform("mvp", mat, required = false)
      screenShader.setUniform("fontHeight", gameState.buffer.fontSize, required = false)
      screenShader.setUniform("time", time, required = false)
      screenShader.setUniform("screenSize", scrSize, required = false)
      render(rectModel)


initTruss("Something", ivec2(1280, 720), keyboardwarrior.init, keyboardwarrior.update, draw, vsync = true)
