# MIT License
#
# Copyright (c) 2024 Jason Beetham
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

import pkg/truss3D/[models, shaders, inputs, fontatlaser, instancemodels, textures]
import pkg/[vmath, truss3D, pixie, opensimplexnoise, chroma, opengl]
import std/[unicode, tables, strutils, enumerate, math]
from std/os import `/`
export chroma

type
  FontRenderObj = object
    fg: int32
    bg: int32
    fontIndex: uint32
    _: int32 # Reserved
    xyzr: Vec4
    wh: Vec4

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
    properties: uint16 # uin16.high different properties, surely we'll never go that high

  Line = object
    glyphs: array[128, Glyph]

iterator items(line: Line): Glyph =
  for glyph in line.glyphs:
    yield glyph

iterator pairs(line: Line): (int, Glyph) =
  for glyph in line.glyphs.pairs:
    yield glyph

iterator mitems(line: var Line): var Glyph =
  for glyph in line.glyphs.mitems:
    yield glyph

type
  BufferMode* = enum
    Text
    Graphics

  ShapeKind* = enum
    Rectangle
    Ellipse
    LinePath
    Character

  Shape* = object
    x, y: float32
    props: uint16
    case kind: ShapeKind
    of Rectangle:
      rectW, rectH: float32
    of Ellipse:
      eRadius1, eRadius2: float32
    of LinePath:
      model: Model
    of Character:
      rune: Rune

  Buffer* = object
    mode*: BufferMode
    pixelHeight: int
    pixelWidth: int
    atlas: FontAtlas
    fontTarget: UiRenderTarget
    textShader: Shader
    graphicShader: Shader

    lines: seq[Line]
    lineHeight*: int
    lineWidth*: int
    cameraPos*: int
    cursorX: int
    cursorY: int

    shapes: seq[Shape] ## Used for graphics mode


    dirtiedColors: bool = true ## Always upload when just instantiated
    colors: seq[Color]
    colorSsbo: SSBO[seq[Color]]
    colorInd: Table[chroma.Color, int]

    cachedProperties: seq[GlyphProperties] ##
      ## We cache properties in a seq to keep them sequential and to reuduce size.
      ## this will need cleared out eventually.
    propToInd: Table[GlyphProperties, uint16]

    time: float32
    properties*: GlyphProperties ## These are for if you do not provide `GlyphProperties`
    noise: OpenSimplex
    useFrameBuffer: bool
    frameBufferSetup: bool
    frameBuffer: FrameBuffer


proc pixelHeight*(buff: Buffer): int = buff.pixelHeight
proc pixelWidth*(buff: Buffer): int = buff.pixelWidth

const
  relativeTextShaderPath {.strDefine.} = ""
  guiVert = ShaderPath relativeTextShaderPath / "text.vert.glsl"
  guiFrag = ShaderPath relativeTextShaderPath / "text.frag.glsl"

proc recalculateBuffer*(buff: var Buffer) =
  let charEntry = buff.atlas.runeEntry(Rune('W'))
  buff.pixelWidth = buff.lineWidth * charEntry.rect.w.int div 2
  buff.pixelHeight = buff.lineHeight * charEntry.rect.h.int div 2
  if buff.lines.len == 0:
    buff.lines.add Line()
  if buff.useFrameBuffer:
    buff.frameBuffer = genFrameBuffer(ivec2(buff.pixelWidth, buff.pixelHeight), tfRgba, wrapMode = ClampedToBorder)

    buff.useFrameBuffer = true
    buff.frameBufferSetup = true

proc initResources*(buff: var Buffer, fontPath: string, useFrameBuffer = false, seedNoise = true) =
  buff.atlas = FontAtlas.init(1024f, 1024f, 5f, readFont(fontPath))
  buff.textShader = loadShader(guiVert, guiFrag)
  var modelData: MeshData[Vec2]
  modelData.appendVerts [vec2(0, 0), vec2(0, 1), vec2(1, 1), vec2(1, 0)].items
  modelData.append [0u32, 1, 2, 0, 2, 3].items
  modelData.appendUv [vec2(0, 1), vec2(0, 0), vec2(1, 0), vec2(1, 1)].items

  buff.fontTarget.model = uploadInstancedModel[RenderInstance](modelData)
  buff.colorSsbo = genSsbo[seq[Color]](1)
  buff.atlas.font.size = 64
  buff.noise =
    if seedNoise:
      newOpenSimplex()
    else:
      newOpenSimplex(0)
  buff.useFrameBuffer = useFrameBuffer
  buff.recalculateBuffer()

proc fontSize*(buff: Buffer): int =  int buff.atlas.font.size

proc setFontSize*(buff: var Buffer, size: int) =
  buff.atlas.setFontSize(size.float32)
  buff.recalculateBuffer()

proc setFont*(buff: var Buffer, font: Font) =
  buff.atlas.setFont(font)
  buff.recalculateBuffer()

proc setLineWidth*(buff: var Buffer, width: int) =
  assert buff.mode == Text
  buff.lineWidth = width
  buff.recalculateBuffer()

proc setLineHeight*(buff: var Buffer, height: int) =
  assert buff.mode == Text
  buff.lineHeight = height
  buff.recalculateBuffer()

proc getColorIndex(buff: var Buffer, color: chroma.Color): int32 =
  buff.colorInd.withValue color, ind:
    return int32 ind[]
  do:
    let colInd = buff.colors.len
    buff.colors.add color
    buff.colorInd[color] = colInd
    buff.dirtiedColors = true
    return int32 colInd

proc getFrameBufferTexture*(buff: Buffer): lent Texture = buff.frameBuffer.colourTexture

proc toggleFrameBuffer*(buff: var Buffer) =
  buff.useFrameBuffer = not buff.useFrameBuffer
  if not buff.framebufferSetup: # TODO: framebuff.id != 0
    buff.recalculateBuffer()

proc usingFrameBuffer*(buff: Buffer): bool = buff.useFrameBuffer

proc uploadTextMode(buff: var Buffer, dt: float32) =
  assert buff.mode == Text
  buff.time += dt
  let scrSize =
    if buff.useFrameBuffer:
      vec2(buff.pixelWidth.float32, buff.pixelHeight.float32)
    else:
      vec2 screenSize()

  var (x, y) = (-1f, 1f - buff.atlas.runeEntry(Rune('+')).rect.h / scrSize.y)
  buff.fontTarget.model.clear()
  var rendered = false
  for ind in buff.cameraPos .. buff.cursorY:
    for xPos, glyph in buff.lines[ind]:
      if xPos > buff.lineWidth:
        break
      let
        prop = buff.cachedProperties[int glyph.properties]
        rune =
          if glyph.rune == Rune(0):
            Rune('+')
          else:
            glyph.rune
        entry = buff.atlas.runeEntry(rune)
        theFg = buff.getColorIndex(prop.foreground)
        theBg = buff.getColorIndex(prop.background)
        size =
          if entry.rect.w == 0:
            buff.atlas.runeEntry(Rune('+')).rect.wh / scrSize
          else:
            entry.rect.wh / scrSize

      if (prop.blinkSpeed == 0 or round(buff.time * prop.blinkSpeed).int mod 2 != 0) and glyph.rune != Rune(0):
        let
          sineOffset = sin((buff.time + x) * prop.sineSpeed) * prop.sineStrength * size.y
          shakeOffsetX =
            if prop.shakeStrength > 0:
              buff.noise.evaluate((buff.time + x * ind.float) * prop.shakeSpeed, float32 ind) * prop.shakeStrength * size.x
            else:
              0
          shakeOffsetY =
            if prop.shakeStrength > 0:
              buff.noise.evaluate((buff.time + y * ind.float) * prop.shakeSpeed, float32 ind) * prop.shakeStrength * size.y
            else:
              0
        rendered = true

        let
          whiteSpaceBit = rune.isWhiteSpace.ord.uint32 shl 31
          id = entry.id.uint32 or whiteSpaceBit
          xyzr = vec4(x + shakeOffsetX, y + sineOffset + shakeOffsetY, 0, 0)
          wh = vec4(size.x, size.y, 0, 0)

        buff.fontTarget.model.push FontRenderObj(
          fg: theFg,
          bg: theBg,
          fontIndex: id,
          xyzr: xyzr,
          wh: wh
          )

      if rune == Rune('\n'):
        break
      elif rune.isWhiteSpace:
        x += buff.atlas.runeEntry(Rune('+')).rect.w / scrSize.x
      else:
        x += size.x

    y -= buff.atlas.runeEntry(Rune('+')).rect.h / scrSize.y
    x = -1f

  if rendered:
    if buff.dirtiedColors:
      buff.colors.copyTo buff.colorSsbo
      buff.dirtiedColors = false

    buff.fontTarget.model.reuploadSsbo()
  buff.frameBuffer.clearColor = buff.properties.background

proc uploadGraphicsMode(buff: var Buffer, dt: float32) =
  assert buff.mode == Graphics

proc upload*(buff: var Buffer, dt: float32) =
  case buff.mode
  of Text:
    buff.uploadTextMode(dt)
  of Graphics:
    buff.uploadGraphicsMode(dt)

proc render*(buff: Buffer) =
  var old: (Glint, Glint, GlSizeI, GlSizeI)
  if buff.useFrameBuffer:
    glGetIntegerv(GlViewPort, old[0].addr)
    glViewport(0, 0, buff.pixelWidth, buff.pixelHeight)
    buff.frameBuffer.clear()
    buff.frameBuffer.bindBuffer()
  buff.colorSsbo.bindBuffer(1)
  buff.atlas.ssbo.bindBuffer(2)
  with buff.textShader:
    glEnable(GlBlend)
    glBlendFunc(GlOne, GlOneMinusSrcAlpha)

    buff.textShader.setUniform("fontTex", buff.atlas.texture)
    buff.fontTarget.model.render()
    glDisable(GlBlend)
  if buff.useFrameBuffer:
    glViewport(old[0], old[1], old[2], old[3])
    unbindFrameBuffer()

proc clearLine*(buff: var Buffer, lineNum: int) =
  ## Writes over `start`
  assert buff.mode == Text
  reset buff.lines[lineNum]

proc clearLine*(buff: var Buffer) =
  ## Writes over `start`
  assert buff.mode == Text
  buff.clearLine(buff.cursorY)
  buff.cursorX = 0

proc clearTo*(buff: var Buffer, line: int) =
  assert buff.mode == Text
  for line in buff.lines.toOpenArray(line, buff.lines.high).mitems:
    reset line

  buff.cursorY = line
  buff.cursorX = 0

  buff.lines.setLen(line + 1)

proc clearTo*(buff: var Buffer, x, y: int) =
  assert buff.mode == Text
  for line in buff.lines.toOpenArray(y + 1, buff.lines.high).mitems:
    reset line

  for glyph in buff.lines[y].glyphs.toOpenArray(x, buff.lines[y].glyphs.high).mitems:
    reset glyph

  buff.lines.setLen(y + 1)
  buff.cursorX = x

proc newLine*(buff: var Buffer) =
  assert buff.mode == Text
  buff.lines.add Line()
  inc buff.cursorY
  buff.cursorX = 0
  if buff.cursorY - buff.cameraPos >= buff.lineHeight:
    buff.cameraPos = buff.lines.len - buff.lineHeight

iterator chr*(s: string): Rune =
  for rune in s.runes:
    yield rune

iterator chr*(s: openarray[Glyph]): Glyph =
  for glyph in s.items:
    yield glyph

proc isNewLine(rune: Rune): bool = rune == Rune '\n'
proc isNewLine(glyph: Glyph): bool = glyph.rune.isNewLine()


proc put*(buff: var Buffer, s: string | openarray[Glyph], props: GlyphProperties, moveCamera = true, getBuffer: static bool = false): auto =
  assert buff.mode == Text
  when getBuffer:
    result = newSeq[Glyph]()

  if buff.lines.len == 0:
    buff.lines.add Line()

  let propInd = buff.propToInd.getOrDefault(props, uint16 buff.cachedProperties.len)

  for rune in s.chr:
    when getBuffer:
      result.add buff.lines[buff.cursorY].glyphs[buff.cursorX]

    if rune.isNewLine():
      buff.lines.add Line()
      buff.cursorX = 0
      inc buff.cursorY
    elif buff.cursorX < buff.lineWidth:
      if propInd == uint16 buff.cachedProperties.len:
        buff.propToInd[props] = propInd
        buff.cachedProperties.add props

      buff.lines[buff.cursorY].glyphs[buff.cursorX] =
        when rune is Rune:
          Glyph(rune: rune, properties: propInd)
        else:
          rune

      inc buff.cursorX

  if moveCamera and buff.cursorY - buff.cameraPos >= buff.lineHeight:
    buff.cameraPos = buff.lines.len - buff.lineHeight

proc put*(buff: var Buffer, s: string, moveCamera = true) =
  put buff, s, buff.properties, moveCamera

proc put*(buff: var Buffer, s: seq[Glyph], props: GlyphProperties, moveCamera = true, getBuffer: static bool = false) = # `seq[Glyph]` != openArray
  buff.put(s.toOpenArray(0, s.high), props, moveCamera, getBuffer)

proc put*(buff: var Buffer, s: seq[Glyph], moveCamera = true) =
  put buff, s, buff.properties, moveCamera

proc drawText*(buff: var Buffer, s: string, x, y, rot, scale: float32, props: GlyphProperties) =
  assert buff.mode == Graphics
  let propInd = buff.propToInd.getOrDefault(props, uint16 buff.cachedProperties.len)
  var (x, y) = (x, y)
  for rune in s.runes:
    buff.shapes.add Shape(
      x: x,
      y: y,
      kind: Character,
      rune: rune,
      props: propInd
    )
    let entry = buff.atlas.runeEntry(rune)
    x += entry.rect.x

proc drawText*(buff: var Buffer, s: string, x, y, rot, scale: float32) =
  buff.drawText(s, x, y, rot, scale, buff.properties)

proc drawText*(buff: var Buffer, s: string, x, y: float32) =
  buff.drawText(s, x, y, 0, 1, buff.properties)

proc drawLine*(buff: var Buffer, points: openArray[Vec2], width: float32, props: GlyphProperties) =
  assert buff.mode == Graphics

proc fetchAndPut*(buff: var Buffer, s: string, moveCamera = true): seq[Glyph] =
  put buff, s, buff.properties, moveCamera, true

proc scrollUp*(buff: var Buffer) =
  assert buff.mode == Text
  buff.cameraPos = max(buff.cameraPos - 1, 0)

proc scrollTo*(buff: var Buffer, pos: int) =
  assert buff.mode == Text
  buff.cameraPos = pos

proc scrollDown*(buff: var Buffer) =
  assert buff.mode == Text
  buff.cameraPos = min(buff.cameraPos + 1, buff.lines.high)

proc toTop*(buff: var Buffer) =
  assert buff.mode == Text
  buff.cameraPos = 0

proc toBottom*(buff: var Buffer) =
  assert buff.mode == Text
  buff.cameraPos = buff.lines.high

proc getPosition*(buff: var Buffer): (int, int) =
  assert buff.mode == Text
  (buff.cursorX, buff.cursorY)

proc setPosition*(buff: var Buffer, x, y: int) =
  assert buff.mode == Text
  (buff.cursorX, buff.cursorY) = (x, y)
  buff.lines.setLen(max(y + 1, buff.lines.len))

template withPos*(buff: var Buffer, x, y: int, body: untyped) =
  assert buff.mode == Text
  ## This moves the buff then returns it back to it's previous position
  let pos = buff.getPosition()
  buff.setPosition(x, y)
  body
  buff.setPosition(pos[0], pos[1])


when isMainModule:
  const clear = color(0, 0, 0, 0)
  var
    buff = Buffer(lineWidth: 40, lineHeight: 40, properties: GlyphProperties(foreground: parseHtmlColor"White", background: clear))
    fontPath = "../PublicPixel.ttf"

  proc init =
    buff.initResources(fontPath)
    startTextInput(default(inputs.Rect), "")
    buff.put("hello world!", GlyphProperties(foreground: parseHtmlColor"Green", background: parseHtmlColor"Yellow", sineSpeed: 5f, sineStrength: 1f))
    buff.put(" bleh \n\n", GlyphProperties(foreground: parseHtmlColor"Green"))
    buff.put("\nHello travllllllerrrrs", GlyphProperties(foreground: parseHtmlColor"Purple", background: parseHtmlColor"Beige", shakeSpeed: 5f, shakeStrength: 0.25f))
    buff.put("\n" & "―".repeat(30), GlyphProperties(foreground: parseHtmlColor"Red", blinkSpeed: 5f))
    buff.put("\n" & "―".repeat(30), GlyphProperties(foreground: parseHtmlColor"White", blinkSpeed: 1f))
    buff.put("\n>")


  proc update(dt: float32) =
    if isTextInputActive():
      if inputText().len > 0:
        buff.put inputText()
        setInputText("")
      if KeyCodeReturn.isDownRepeating():
        buff.put("\n>")
    if KeyCodeUp.isDownRepeating():
      buff.scrollUp()
    if KeyCodeDown.isDownRepeating():
      buff.scrollDown()
    buff.upload(dt)

  proc draw =
    buff.render()
  initTruss("Something", ivec2(buff.pixelWidth, buff.pixelHeight), init, update, draw, vsync = true)
