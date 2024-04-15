import pkg/truss3D/[models, shaders, inputs, fontatlaser, instancemodels]
import pkg/[vmath, truss3D, pixie, opensimplexnoise]
import std/[unicode, colors, tables, strutils, enumerate, math]
export colors

type
  FontRenderObj = object
    fg: int32
    bg: int32
    fontIndex: uint32
    _: int32# Reserved
    matrix* {.align: 16.}: Mat4

  RenderInstance = seq[FontRenderObj]

  UiRenderTarget = object
    model: InstancedModel[RenderInstance]
    shader: Shader

  GlyphProperties* = object
    shakeSpeed*: float32
    shakeStrength*: float32
    blinkSpeed*: float32
    sineSpeed*: float32
    sineStrength*: float32
    foreground*, background*: colors.Color

  Glyph* = object
    rune: Rune
    properties: GlyphProperties

  Line = object
    len: int
    glyphs: array[128, Glyph]

iterator items(line: Line): Glyph =
  for i in 0..<line.len:
    yield line.glyphs[i]

iterator mitems(line: var Line): var Glyph =
  for i in 0..<line.len:
    yield line.glyphs[i]

type
  Buffer* = object
    lines: seq[Line]
    pixelHeight*: 0..1024
    pixelWidth*: 0..1024
    lineHeight: int
    lineWidth: int
    cameraPos: int
    atlas: FontAtlas
    shader: Shader
    fontTarget: UiRenderTarget
    colors: seq[Vec4]
    colorSsbo: SSBO[seq[Vec4]]
    colorInd: Table[colors.Color, int]
    time: float32
    properties*: GlyphProperties ## These are for if you do not provide `GlyphProperties`
    noise: OpenSimplex

const
  guiVert = ShaderPath"text.vert.glsl"
  guiFrag = ShaderPath"text.frag.glsl"

proc initResources*(buffer: var Buffer, fontPath: string) =
  buffer.atlas = FontAtlas.init(1024f, 1024f, 3f, readFont(fontPath))
  buffer.shader = loadShader(guiVert, guiFrag)
  var modelData: MeshData[Vec2]
  modelData.appendVerts [vec2(0, 0), vec2(0, 1), vec2(1, 1), vec2(1, 0)].items
  modelData.append [0u32, 1, 2, 0, 2, 3].items
  modelData.appendUv [vec2(0, 1), vec2(0, 0), vec2(1, 0), vec2(1, 1)].items

  buffer.fontTarget.model = uploadInstancedModel[RenderInstance](modelData)
  buffer.colorSsbo = genSsbo[seq[Vec4]](1)
  buffer.atlas.font.size = 15

  let charEntry = buffer.atlas.runeEntry(Rune('+'))
  buffer.lineWidth = buffer.pixelWidth div charEntry.rect.w.int * 2 - 1
  buffer.lineHeight = buffer.pixelHeight div charEntry.rect.h.int * 2 - 1
  buffer.lines.add Line()
  buffer.noise = newOpenSimplex()

proc getColorIndex(buffer: var Buffer, color: colors.Color): int32 =
  if color notin buffer.colorInd:
    let colInd = buffer.colors.len
    var col = color.extractRgb
    buffer.colors.add vec4(col.r / 255, col.g / 255, col.b / 255, 1)
    colInd
  else:
    buffer.colorInd[color]

template mixCol(argA, argB: colors.Color, body: untyped): untyped =
  template `><` (x: untyped): untyped =
    # keep it in the range 0..255
    block:
      var y = x # eval only once
      if y >% 255:
        y = if y < 0: 0 else: 255
      y

  template mixxer(a {.inject.}: int, b {.inject.}: int): int =
    body

  var colA = argA.extractRgb
  for _, fieldA, fieldB in fieldPairs(colA, argB.extractRgb):
    fieldA = `><`(mixxer(fieldA, fieldB))
  rgb(colA.r, colA.g, colA.b)

proc upload*(buffer: var Buffer, dt: float32) =
  buffer.time += dt
  let scrSize = vec2 screenSize()
  var (x, y) = (-1f, 1f - buffer.atlas.runeEntry(Rune('+')).rect.h / scrSize.y)
  buffer.fontTarget.model.clear()
  var rendered = false
  for ind in buffer.cameraPos .. buffer.lines.high:
    for glyph in buffer.lines[ind]:
      rendered = true

      let
        entry = buffer.atlas.runeEntry(glyph.rune)
        theFg = buffer.getColorIndex:
          mixCol(glyph.properties.foreground, colBlack):
            if glyph.properties.blinkSpeed != 0 and round(buffer.time * glyph.properties.blinkSpeed).int mod 2 == 0:
              b
            else:
              a
        theBg = buffer.getColorIndex(glyph.properties.background)
        size = entry.rect.wh / scrSize
      let
        sineOffset = sin((buffer.time + x) * glyph.properties.sineSpeed) * glyph.properties.sineStrength * size.y
        shakeOffsetX = buffer.noise.evaluate(buffer.time + x * glyph.properties.shakeSpeed, float32 ind) * glyph.properties.shakeStrength * size.x
        shakeOffsetY = buffer.noise.evaluate(buffer.time + y * glyph.properties.shakeSpeed, float32 ind) * glyph.properties.shakeStrength * size.y
      buffer.fontTarget.model.push FontRenderObj(fg: theFg, bg: theBg, fontIndex: uint32 entry.id, matrix:  translate(vec3(x + shakeOffsetX, y + sineOffset + shakeOffsetY, 0)) * scale(vec3(size, 1)))
      if glyph.rune == Rune('\n'):
        y -= buffer.atlas.runeEntry(Rune('+')).rect.h / scrSize.y
        x = -1f
        break
      elif glyph.rune.isWhiteSpace:
        x += buffer.atlas.runeEntry(Rune('+')).rect.w / scrSize.x
      else:
        x += size.x

  if rendered:
    buffer.colors.copyTo buffer.colorSsbo
    buffer.fontTarget.model.reuploadSsbo()

proc render*(buffer: Buffer) =
  buffer.colorSsbo.bindBuffer(1)
  buffer.atlas.ssbo.bindBuffer(2)
  with buffer.shader:
    glEnable(GlBlend)
    buffer.shader.setUniform("fontTex", buffer.atlas.texture)
    glBlendFunc(GlOne, GlOneMinusSrcAlpha)
    buffer.fontTarget.model.render()
    glDisable(GlBlend)

proc clearLine*(buff: var Buffer, lineNum: int) =
  ## Writes over `start`
  buff.lines[lineNum].len = 0

proc clearLine*(buff: var Buffer) =
  ## Writes over `start`
  buff.lines[^1].len = 0

proc put*(buff: var Buffer, s: string, props: GlyphProperties) =
  for rune in s.runes:
    buff.lines[^1].glyphs[buff.lines[^1].len] = Glyph(rune: rune, properties: props)
    inc buff.lines[^1].len
    if rune == Rune '\n':
      buff.lines.add Line()

  if buff.lines.high - buff.cameraPos > buff.lineHeight:
    buff.cameraPos = buff.lines.high - buff.lineHeight

proc put*(buff: var Buffer, s: string) =
  put buff, s, buff.properties


proc scrollUp*(buff: var Buffer) =
  buff.cameraPos = max(buff.cameraPos - 1, 0)

proc scrollDown*(buff: var Buffer) =
  buff.cameraPos = min(buff.cameraPos + 1, buff.lines.high)

when isMainModule:
  var
    buffer = Buffer(pixelWidth: 320, pixelHeight: 240, properties: GlyphProperties(foreground: colWhite, background: colBlack))
    fontPath = "PublicPixel.ttf"

  proc init =
    buffer.initResources(fontPath)
    startTextInput(default(inputs.Rect), "")
    buffer.put("hello world!", GlyphProperties(foreground: colGreen, background: colYellow, sineSpeed: 5f, sineStrength: 1f))
    buffer.put(" bleh \n\n", GlyphProperties(foreground: colGreen))
    buffer.put("\nHello travllllllerrrrs", GlyphProperties(foreground: colPurple, background: colBeige, shakeSpeed: 5f, shakeStrength: 0.25f))
    buffer.put("\n" & "―".repeat(30), GlyphProperties(foreground: colRed, blinkSpeed: 5f))
    buffer.put("\n" & "―".repeat(30), GlyphProperties(foreground: colWhite, blinkSpeed: 1f))
    buffer.put("\n>")


  proc update(dt: float32) =
    if isTextInputActive():
      if inputText().len > 0:
        buffer.put inputText()
        setInputText("")
      if KeyCodeReturn.isDownRepeating():
        buffer.put("\n>")
    if KeyCodeUp.isDownRepeating():
      buffer.scrollUp()
    if KeyCodeDown.isDownRepeating():
      buffer.scrollDown()
    buffer.upload(dt)

  proc draw =
    buffer.render()
  initTruss("Something", ivec2(buffer.pixelWidth, buffer.pixelHeight), init, update, draw, vsync = true)
