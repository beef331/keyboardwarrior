import pkg/truss3D/[models, shaders, inputs, fontatlaser, instancemodels]
import pkg/[vmath, truss3D, pixie]
import std/[unicode, colors, tables, strutils, enumerate]
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

  GlyphFlag* = enum
    Shake # Moves around
    Dim
    Bold
    Blink

  GlyphProperties* = object
    flag*: set[GlyphFlag]

  Glyph* = object
    rune: Rune
    foreground, background: colors.Color

  Line = object
    len: int
    glyphs: array[128, Glyph]

  Buffer* = object
    glyphs: seq[Glyph]
    pixelHeight*: 0..1024
    pixelWidth*: 0..1024
    lineHeight: int
    lineWidth: int
    cameraPos: int
    entryPos: int
    linesAdded: int
    atlas: FontAtlas
    shader: Shader
    fontTarget: UiRenderTarget
    colors: seq[Vec4]
    colorSsbo: SSBO[seq[Vec4]]
    colorInd: Table[colors.Color, int]

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
  buffer.lineWidth = buffer.pixelWidth div charEntry.rect.w.int
  buffer.lineHeight = buffer.pixelHeight div charEntry.rect.h.int

proc getColorIndex(buffer: var Buffer, color: colors.Color): int32 =
  if color notin buffer.colorInd:
    let colInd = buffer.colors.len
    var col = color.extractRgb
    buffer.colors.add vec4(col.r / 255, col.g / 255, col.b / 255, 1)
    colInd
  else:
    buffer.colorInd[color]

proc upload*(buffer: var Buffer) =
  let
    scrSize = vec2 screenSize()
    halfSize = scrSize / 2
  var (x, y) = (-1f, 1f - buffer.atlas.runeEntry(Rune('+')).rect.h / scrSize.y)
  buffer.fontTarget.model.clear()
  var linesRendered = 0
  for ind in buffer.cameraPos .. buffer.glyphs.high:
    let
      glyph = buffer.glyphs[ind]
      entry = buffer.atlas.runeEntry(glyph.rune)
      fg = buffer.getColorIndex(glyph.foreground)
      bg = buffer.getColorIndex(glyph.background)
      size = entry.rect.wh / scrSize

    buffer.fontTarget.model.push FontRenderObj(fg: fg, bg: bg, fontIndex: uint32 entry.id, matrix:  translate(vec3(x, y, 0)) * scale(vec3(size, 1)))
    if glyph.rune == Rune('\n'):
      y -= buffer.atlas.runeEntry(Rune('+')).rect.h / scrSize.y
      inc linesRendered
      if linesRendered > buffer.lineHeight:
        break
      x = -1f
    elif glyph.rune.isWhiteSpace:
      x += buffer.atlas.runeEntry(Rune('+')).rect.w / scrSize.x
    else:
      x += size.x


  if buffer.glyphs.len > 0 and (buffer.cameraPos..buffer.glyphs.high).len > 0:
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

proc writeOver*(buff: var Buffer, start: int, str: string, foreground: colors.Color, background = colBlack) =
  ## Writes over `start`
  let strLen = str.runeLen
  if start + strLen >= buff.glyphs.len:
    buff.glyphs.setLen(strLen)

  for i, rune in enumerate str.runes:
    buff.glyphs[start + i] = Glyph(rune: rune, foreground: foreground, background: background)

proc put*(buff: var Buffer, s: string, foreground: colors.Color, background = colBlack) =
  for rune in s.runes:
    buff.glyphs.add Glyph(rune: rune, foreground: foreground, background: background)
    if rune == Rune '\n':
      inc buff.linesAdded
      buff.entryPos = buff.glyphs.len

  if buff.linesAdded >= buff.lineHeight:
    var found = 0
    for ind in buff.cameraPos .. buff.glyphs.high:
      let glyph = buff.glyphs[ind]
      if glyph.rune == Rune '\n':
        inc found
      if buff.linesAdded - found < buff.lineHeight:
        buff.cameraPos = ind + 1
        break
    buff.linesAdded -= found

proc entryIndex*(buff: var Buffer): int = buff.entryPos

proc scrollUp*(buff: var Buffer) =
  for ind in countDown(buff.cameraPos - 2, 0):
    if (buff.glyphs[ind].rune == Rune '\n'):
      buff.cameraPos = ind + 1
      return
    if ind == 0:
      buff.cameraPos = 0

proc scrollDown*(buff: var Buffer) =
  if buff.cameraPos + 1 >= buff.entryPos:
    buff.cameraPos = buff.entryPos

  for ind in countUp(buff.cameraPos, buff.entryPos):
    if buff.glyphs[ind].rune == Rune '\n':
      buff.cameraPos = ind + 1
      return


when isMainModule:
  var
    buffer = Buffer(pixelWidth: 320, pixelHeight: 240)
    fontPath = "PublicPixel.ttf"

  proc init =
    buffer.initResources(fontPath)
    startTextInput(default(inputs.Rect), "")
    buffer.put("hello world!", colGreen, colYellow)
    buffer.put(" bleh", colRed)
    buffer.put("\nHello travllllllerrrrs", colPurple, colBeige)
    buffer.put("\n" & "―".repeat(30), colRed)
    buffer.put("\n>", colWhite)


  proc update(dt: float32) =
    if isTextInputActive():
      if inputText().len > 0:
        buffer.put inputText(), colWhite
        setInputText("")

      if KeycodeBackspace.isDownRepeating() and buffer.glyphs.high >= 0:
        buffer.glyphs.setLen(buffer.glyphs.high)
      elif KeyCodeReturn.isDownRepeating():
        buffer.put("\n>", colWhite)
    if KeyCodeUp.isDownRepeating():
      buffer.scrollUp()
    if KeyCodeDown.isDownRepeating():
      buffer.scrollDown()
    buffer.upload()

  proc draw =
    buffer.render()
  initTruss("Something", ivec2(buffer.pixelWidth, buffer.pixelHeight), init, update, draw, vsync = true)
