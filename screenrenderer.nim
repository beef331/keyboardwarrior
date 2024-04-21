import pkg/truss3D/[models, shaders, inputs, fontatlaser, instancemodels, textures]
import pkg/[vmath, truss3D, pixie, opensimplexnoise, chroma, opengl]
import std/[unicode, tables, strutils, enumerate, math]
export chroma

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
    foreground*, background*: Color

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
    pixelHeight: int
    pixelWidth: int
    lineHeight*: int
    lineWidth*: int
    cameraPos*: int
    atlas: FontAtlas
    shader: Shader
    fontTarget: UiRenderTarget
    colors: seq[Color]
    colorSsbo: SSBO[seq[Color]]
    colorInd: Table[chroma.Color, int]
    time: float32
    properties*: GlyphProperties ## These are for if you do not provide `GlyphProperties`
    noise: OpenSimplex
    useFrameBuffer: bool
    frameBufferSetup: bool
    frameBuffer: FrameBuffer

proc pixelHeight*(buffer: Buffer): int = buffer.pixelHeight
proc pixelWidth*(buffer: Buffer): int = buffer.pixelWidth

const
  guiVert = ShaderPath"text.vert.glsl"
  guiFrag = ShaderPath"text.frag.glsl"

proc recalculateBuffer*(buffer: var Buffer) =
  let charEntry = buffer.atlas.runeEntry(Rune('W'))
  buffer.pixelWidth = buffer.lineWidth * charEntry.rect.w.int div 2
  buffer.pixelHeight = buffer.lineHeight * charEntry.rect.h.int div 2
  if buffer.lines.len == 0:
    buffer.lines.add Line()
  if buffer.useFrameBuffer:
    buffer.frameBuffer = genFrameBuffer(ivec2(buffer.pixelWidth, buffer.pixelHeight), tfRgba)

    buffer.useFrameBuffer = true
    buffer.frameBufferSetup = true


proc initResources*(buffer: var Buffer, fontPath: string, useFrameBuffer = false) =
  buffer.atlas = FontAtlas.init(1024f, 1024f, 5f, readFont(fontPath))
  buffer.shader = loadShader(guiVert, guiFrag)
  var modelData: MeshData[Vec2]
  modelData.appendVerts [vec2(0, 0), vec2(0, 1), vec2(1, 1), vec2(1, 0)].items
  modelData.append [0u32, 1, 2, 0, 2, 3].items
  modelData.appendUv [vec2(0, 1), vec2(0, 0), vec2(1, 0), vec2(1, 1)].items

  buffer.fontTarget.model = uploadInstancedModel[RenderInstance](modelData)
  buffer.colorSsbo = genSsbo[seq[Color]](1)
  buffer.atlas.font.size = 64
  buffer.noise = newOpenSimplex()
  buffer.useFrameBuffer = useFrameBuffer
  buffer.recalculateBuffer()

proc fontSize*(buffer: Buffer): int =  int buffer.atlas.font.size

proc setFontSize*(buffer: var Buffer, size: int) =
  buffer.atlas.setFontSize(size.float32)
  buffer.recalculateBuffer()

proc setFont*(buffer: var Buffer, font: Font) =
  buffer.atlas.setFont(font)
  buffer.recalculateBuffer()

proc setLineWidth*(buffer: var Buffer, width: int) =
  buffer.lineWidth = width
  buffer.recalculateBuffer()

proc setLineHeight*(buffer: var Buffer, height: int) =
  buffer.lineHeight = height
  buffer.recalculateBuffer()

proc getColorIndex(buffer: var Buffer, color: chroma.Color): int32 =
  if color notin buffer.colorInd:
    let colInd = buffer.colors.len
    buffer.colors.add color
    colInd
  else:
    buffer.colorInd[color]

proc getFrameBufferTexture*(buffer: Buffer): lent Texture = buffer.frameBuffer.colourTexture

proc toggleFrameBuffer*(buffer: var Buffer) =
  buffer.useFrameBuffer = not buffer.useFrameBuffer
  if not buffer.framebufferSetup: # TODO: framebuffer.id != 0
    buffer.frameBuffer = genFrameBuffer(ivec2(buffer.pixelWidth, buffer.pixelHeight), tfRgba)
    buffer.frameBuffer.clearColor = color(0, 0, 0, 0)
    buffer.frameBufferSetup = true

proc usingFrameBuffer*(buff: Buffer): bool = buff.useFrameBuffer

proc upload*(buffer: var Buffer, dt: float32) =
  buffer.time += dt
  let scrSize =
    if buffer.useFrameBuffer:
      vec2(buffer.pixelWidth.float32, buffer.pixelHeight.float32)
    else:
      vec2 screenSize()

  var (x, y) = (-1f, 1f - buffer.atlas.runeEntry(Rune('+')).rect.h / scrSize.y)
  buffer.fontTarget.model.clear()
  var rendered = false
  for ind in buffer.cameraPos .. buffer.lines.high:
    for glyph in buffer.lines[ind]:
      let
        entry = buffer.atlas.runeEntry(glyph.rune)
        theFg = buffer.getColorIndex(glyph.properties.foreground)
        theBg = buffer.getColorIndex(glyph.properties.background)
        size = entry.rect.wh / scrSize
      let
        sineOffset = sin((buffer.time + x) * glyph.properties.sineSpeed) * glyph.properties.sineStrength * size.y
        shakeOffsetX = buffer.noise.evaluate((buffer.time + x * ind.float) * glyph.properties.shakeSpeed, float32 ind) * glyph.properties.shakeStrength * size.x
        shakeOffsetY = buffer.noise.evaluate((buffer.time + y * ind.float) * glyph.properties.shakeSpeed, float32 ind) * glyph.properties.shakeStrength * size.y
      if glyph.properties.blinkSpeed == 0 or round(buffer.time * glyph.properties.blinkSpeed).int mod 2 != 0:
        rendered = true
        buffer.fontTarget.model.push FontRenderObj(fg: theFg, bg: theBg, fontIndex: uint32 entry.id, matrix:  translate(vec3(x + shakeOffsetX, y + sineOffset + shakeOffsetY, 0)) * scale(vec3(size, 1)))
      if glyph.rune == Rune('\n'):
        break
      elif glyph.rune.isWhiteSpace:
        x += buffer.atlas.runeEntry(Rune('+')).rect.w / scrSize.x
      else:
        x += size.x
    y -= buffer.atlas.runeEntry(Rune('+')).rect.h / scrSize.y
    x = -1f

  if rendered:
    buffer.colors.copyTo buffer.colorSsbo
    buffer.fontTarget.model.reuploadSsbo()
  buffer.frameBuffer.clearColor = buffer.properties.background


proc render*(buffer: Buffer) =
  var old: (Glint, Glint, GlSizeI, GlSizeI)
  if buffer.useFrameBuffer:
    glGetIntegerv(GlViewPort, old[0].addr)
    glViewport(0, 0, buffer.pixelWidth, buffer.pixelHeight)
    buffer.frameBuffer.clear()
    buffer.frameBuffer.bindBuffer()
  buffer.colorSsbo.bindBuffer(1)
  buffer.atlas.ssbo.bindBuffer(2)
  with buffer.shader:
    glEnable(GlBlend)
    glBlendFunc(GlOne, GlOneMinusSrcAlpha)

    buffer.shader.setUniform("fontTex", buffer.atlas.texture)
    buffer.fontTarget.model.render()
    glDisable(GlBlend)
  if buffer.useFrameBuffer:
    glViewport(old[0], old[1], old[2], old[3])
    unbindFrameBuffer()

proc clearLine*(buff: var Buffer, lineNum: int) =
  ## Writes over `start`
  buff.lines[lineNum].len = 0

proc clearLine*(buff: var Buffer) =
  ## Writes over `start`
  buff.lines[^1].len = 0

proc clearTo*(buff: var Buffer, line: int) =
  for line in buff.lines.toOpenArray(line, buff.lines.high).mitems:
    line.len = 0

  buff.lines.setLen(line + 1)

proc getPosition*(buff: var Buffer): (int, int) =
  (buff.lines[^1].len - 1, buff.lines.high)

proc newLine*(buff: var Buffer) =
  buff.lines.add Line()
  if buff.lines.high - buff.cameraPos >= buff.lineHeight:
    buff.cameraPos = buff.lines.len - buff.lineHeight

proc put*(buff: var Buffer, s: string, props: GlyphProperties) =
  if buff.lines.len == 0:
    buff.lines.add Line()
  for rune in s.runes:
    if buff.lines[^1].len < buff.lineWidth:
      buff.lines[^1].glyphs[buff.lines[^1].len] = Glyph(rune: rune, properties: props)
      inc buff.lines[^1].len
    if rune == Rune '\n':
      buff.lines.add Line()

  if buff.lines.high - buff.cameraPos >= buff.lineHeight:
    buff.cameraPos = buff.lines.len - buff.lineHeight

proc put*(buff: var Buffer, s: string) =
  put buff, s, buff.properties

proc scrollUp*(buff: var Buffer) =
  buff.cameraPos = max(buff.cameraPos - 1, 0)

proc scrollDown*(buff: var Buffer) =
  buff.cameraPos = min(buff.cameraPos + 1, buff.lines.high)

proc toTop*(buffer: var Buffer) =
  buffer.cameraPos = 0

proc toBottom*(buffer: var Buffer) =
  buffer.cameraPos = buffer.lines.high

when isMainModule:
  const clear = color(0, 0, 0, 0)
  var
    buffer = Buffer(pixelWidth: 320, pixelHeight: 240, properties: GlyphProperties(foreground: parseHtmlColor"White", background: clear))
    fontPath = "PublicPixel.ttf"

  proc init =
    buffer.initResources(fontPath)
    startTextInput(default(inputs.Rect), "")
    buffer.put("hello world!", GlyphProperties(foreground: parseHtmlColor"Green", background: parseHtmlColor"Yellow", sineSpeed: 5f, sineStrength: 1f))
    buffer.put(" bleh \n\n", GlyphProperties(foreground: parseHtmlColor"Green"))
    buffer.put("\nHello travllllllerrrrs", GlyphProperties(foreground: parseHtmlColor"Purple", background: parseHtmlColor"Beige", shakeSpeed: 5f, shakeStrength: 0.25f))
    buffer.put("\n" & "―".repeat(30), GlyphProperties(foreground: parseHtmlColor"Red", blinkSpeed: 5f))
    buffer.put("\n" & "―".repeat(30), GlyphProperties(foreground: parseHtmlColor"White", blinkSpeed: 1f))
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
