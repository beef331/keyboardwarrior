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
import watchedshaders

export chroma

const screenRendererLineLength {.strdefine.} = 256

type
  FontRenderObj = object
    fg: int32
    bg: int32
    fontIndex: uint32
      ## MSB is used for "isWhiteSpace"
      ## In Graphics mode the last 4 bits are used for ShapeKind
    _: int32 # Reserved
    xyzr: Vec4
    wh: Vec4

  RenderInstance = seq[FontRenderObj]

  UiRenderTarget = object
    model: InstancedModel[RenderInstance]

  GlyphProperties* = object
    shakeSpeed*: float32
    shakeStrength*: float32
    blinkSpeed*: float32
    sineSpeed*: float32
    sineStrength*: float32
    displaySpeed*: float32
    foreground*, background*: Color

  Glyph* = object
    rune: Rune
    properties: uint16 # uin16.high different properties, surely we'll never go that high
    timeToDisplay: float32

  Line* = object
    glyphs*: array[screenRendererLineLength, Glyph]

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
    Character # Always needs to be first
    Rectangle
    OutlineRectangle
    Ellipse
    OutlineEllipse
    LinePath

  Shape* = object
    x, y: float32
    scale: float32
    props: uint16
    case kind: ShapeKind
    of Rectangle, OutlineRectangle:
      rectW, rectH: float32
    of Ellipse, OutlineEllipse:
      eRadius1, eRadius2: float32
    of LinePath:
      model: Model
    of Character:
      rune: Rune

  Buffer* = object
    mode*: BufferMode
    pixelHeight: int
    pixelWidth: int
    atlas: ref FontAtlas
    fontTarget: UiRenderTarget
    textShader: WatchedShader
    graphicShader: WatchedShader

    lines: seq[Line]
    lineHeight*: int
    lineWidth*: int
    cameraPos*: int
    cursorX: int
    cursorY: int

    shapes: seq[Shape] ## Used for graphics mode

    groupPrint: bool # Consider the following until reset as joined in a single block
    groupIndex: int # Rune index


    dirtiedColors: bool = true ## Always upload when just instantiated
    colors: ref seq[Color]
    colorSsbo: ref SSBO[seq[Color]]
    colorInd: ref Table[chroma.Color, int]

    cachedProperties: ref seq[GlyphProperties] ##
      ## We cache properties in a seq to keep them sequential and to reuduce size.
      ## this will need cleared out eventually.
    propToInd: ref Table[GlyphProperties, uint16]

    time: float32
    properties*: GlyphProperties ## These are for if you do not provide `GlyphProperties`
    noise: OpenSimplex
    useFrameBuffer: bool
    frameBufferSetup: bool
    frameBuffer: FrameBuffer

    graphicCursorX: int = -1
    graphicCursorY: int = -1


template grouped*(buff: var Buffer, body: typed): untyped =
  buff.groupIndex = 0
  buff.groupPrint = true
  body
  buff.groupPrint = false
  buff.groupIndex = 0

proc `$`(b: Buffer): string = "..."

proc pixelHeight*(buff: Buffer): int = buff.pixelHeight
proc pixelWidth*(buff: Buffer): int = buff.pixelWidth

const
  relativeTextShaderPath {.strDefine.} = ""
  guiVert = relativeTextShaderPath / "text.vert.glsl"
  guiFrag = relativeTextShaderPath / "text.frag.glsl"
  shapeFrag = relativeTextShaderPath / "shape.frag.glsl"


proc recalculateBuffer*(buff: var Buffer) =
  let charEntry = buff.atlas[].runeEntry(Rune('W'))
  buff.pixelWidth = buff.lineWidth * charEntry.rect.w.int div 2
  buff.pixelHeight = buff.lineHeight * charEntry.rect.h.int div 2
  if buff.lines.len == 0:
    buff.lines.add Line()
  if buff.useFrameBuffer:
    buff.frameBuffer = genFrameBuffer(ivec2(buff.pixelWidth, buff.pixelHeight), tfRgba, wrapMode = ClampedToBorder)

    buff.useFrameBuffer = true
    buff.frameBufferSetup = true

proc fontSize*(buff: Buffer): int =  int buff.atlas.font.size

proc getColorIndex(buff: var Buffer, color: chroma.Color): int32 =
  buff.colorInd[].withValue color, ind:
    return int32 ind[]
  do:
    let colInd = buff.colors[].len
    buff.colors[].add color
    buff.colorInd[color] = colInd
    buff.dirtiedColors = true
    return int32 colInd

proc getPropertyIndex(buff: var Buffer, prop: GlyphProperties): uint16 =
  buff.propToInd[].withValue prop, val:
    return val[]
  do:
    let ind = uint16 buff.cachedProperties[].len
    buff.cachedProperties[].add prop
    buff.propToInd[prop] = ind
    return ind

proc initResources*(buff: var Buffer, font: Font, useFrameBuffer = false, seedNoise = true, fontSize = 80) =
  for field in buff.fields:
    when field is ref:
      new field

  let font =
    when font is Font:
      font
    else:
      readFont(font)

  buff.atlas[] = FontAtlas.init(1024f, 1024f, 5f, font)
  buff.textShader = loadWatchedShader(guiVert, guiFrag)
  buff.graphicShader = loadWatchedShader(guiVert, shapeFrag)
  var modelData: MeshData[Vec2]
  modelData.appendVerts [vec2(0, 0), vec2(0, 1), vec2(1, 1), vec2(1, 0)].items
  modelData.append [0u32, 1, 2, 0, 2, 3].items
  modelData.appendUv [vec2(0, 1), vec2(0, 0), vec2(1, 0), vec2(1, 1)].items

  buff.fontTarget.model = uploadInstancedModel[RenderInstance](modelData)
  buff.colorSsbo[] = genSsbo[seq[Color]](1)
  buff.atlas.font.size = float fontSize
  buff.noise =
    if seedNoise:
      newOpenSimplex()
    else:
      newOpenSimplex(0)
  buff.useFrameBuffer = useFrameBuffer
  buff.recalculateBuffer()

proc initResources*(buff: var Buffer, fontPath: string, useFrameBuffer = false, seedNoise = true, fontSize = 80) =
  buff.initResources(readFont(fontPath), useFrameBuffer, seedNoise, fontSize)



proc initFrom*(buff: var Buffer, source: Buffer, seedNoise = true) =
  for a, b in buff.fields(source):
    when a is ref:
      a = b

  var modelData: MeshData[Vec2]
  modelData.appendVerts [vec2(0, 0), vec2(0, 1), vec2(1, 1), vec2(1, 0)].items
  modelData.append [0u32, 1, 2, 0, 2, 3].items
  modelData.appendUv [vec2(0, 1), vec2(0, 0), vec2(1, 0), vec2(1, 1)].items

  buff.fontTarget.model = uploadInstancedModel[RenderInstance](modelData)

  buff.lineWidth = source.lineWidth
  buff.lineHeight = source.lineHeight
  buff.properties = source.properties
  buff.noise =
    if seedNoise:
      newOpenSimplex()
    else:
      newOpenSimplex(0)
  buff.useFrameBuffer = source.useFrameBuffer
  buff.recalculateBuffer()


proc setFontSize*(buff: var Buffer, size: int) =
  buff.atlas[].setFontSize(size.float32)
  buff.recalculateBuffer()

proc setFont*(buff: var Buffer, font: Font) =
  buff.atlas[].setFont(font)
  buff.recalculateBuffer()

proc setLineWidth*(buff: var Buffer, width: int) =
  buff.lineWidth = width
  buff.recalculateBuffer()

proc setLineHeight*(buff: var Buffer, height: int) =
  buff.lineHeight = height
  buff.recalculateBuffer()

proc getFrameBufferTexture*(buff: Buffer): lent Texture = buff.frameBuffer.colourTexture

proc toggleFrameBuffer*(buff: var Buffer) =
  buff.useFrameBuffer = not buff.useFrameBuffer
  if not buff.framebufferSetup: # TODO: framebuff.id != 0
    buff.recalculateBuffer()

proc usingFrameBuffer*(buff: Buffer): bool = buff.useFrameBuffer

proc propIsVisible(buff: Buffer, prop: GlyphProperties): bool =
  prop.blinkSpeed == 0 or round(buff.time * prop.blinkSpeed).int mod 2 != 0

proc glyphIsVisible(buff: Buffer, prop: GlyphProperties, glyph: Glyph): bool =
  buff.propIsVisible(prop) and glyph.rune != Rune(0) and glyph.timeToDisplay <= 0

proc runeSize*(buffer: var Buffer): Vec2 =
  let entry = buffer.atlas[].runeEntry(Rune '+')
  vec2(entry.rect.w, entry.rect.h)

proc uploadRune*(buff: var Buffer, scrSize: Vec2, x, y: float32, glyph: Glyph, ind: int, scale = 1f32, offset: static bool = false): (bool, Rune, Vec2) =
  let
    prop = buff.cachedProperties[int glyph.properties]
    rune =
      if glyph.rune == Rune(0):
        Rune('+')
      else:
        glyph.rune
    entry = buff.atlas[].runeEntry(rune)
    theFg = buff.getColorIndex(prop.foreground)
    theBg = buff.getColorIndex(prop.background)
    size =
      if entry.rect.w == 0:
        buff.runeSize * (scale / scrSize)
      else:
        entry.rect.wh * (scale / scrSize)

  when offset:
    let
      x = x - size.x / 2
      y = y - size.y / 2

  result = (
    buff.glyphIsVisible(prop, glyph),
    rune,
    size
  )
  if result[0]:
    let
      sineOffset = sin((buff.time + x) * prop.sineSpeed) * prop.sineStrength / scrSize.y
      shakeOffsetX =
        if prop.shakeStrength > 0:
          buff.noise.evaluate((buff.time + x * ind.float) * prop.shakeSpeed, float32 ind) * prop.shakeStrength / scrSize.y
        else:
          0
      shakeOffsetY =
        if prop.shakeStrength > 0:
          buff.noise.evaluate((buff.time + y * ind.float) * prop.shakeSpeed, float32 ind) * prop.shakeStrength / scrSize.y
        else:
          0

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

proc clearShapes*(buff: var Buffer) = buff.shapes.setLen(0)

proc uploadTextMode(buff: var Buffer, screenSize: Vec2, dt: float32) =
  assert buff.mode == Text
  let
    scrSize =
      if buff.useFrameBuffer:
        vec2(buff.pixelWidth.float32, buff.pixelHeight.float32)
      else:
        screenSize
    nonPrintableSize = buff.atlas[].runeEntry(Rune('+')).rect
  let (startX, startY) = (-1f, 1f - nonPrintableSize.h / scrSize.y)
  var (x, y) = (startX, startY)
  buff.fontTarget.model.clear()
  var rendered = false
  for ind in buff.cameraPos .. buff.cursorY:
    for xPos, glyph in buff.lines[ind].glyphs.mpairs:
      glyph.timeToDisplay -= dt
      if xPos > buff.lineWidth:
        break
      var (thisRendered, rune, size) = buff.uploadRune(scrSize, x, y, glyph, ind)
      rendered = thisRendered or rendered

      if rune == Rune('\n'):
        break
      elif rune.isWhiteSpace:
        x += nonPrintableSize.w / scrSize.x
      else:
        x += size.x

    y -= nonPrintableSize.h / scrSize.y
    x = -1f


  if buff.graphicCursorX != -1 and buff.graphicCursorY != -1:
    let
      cursX = startX + buff.graphicCursorX.float32 * nonPrintableSize.w / scrSize.x
      cursY = startY - (buff.graphicCursorY - buff.cameraPos).float32 * nonPrintableSize.h / scrSize.y
    var prop = buff.properties
    prop.blinkSpeed = 3
    prop.background.a = 0
    let propInd = buff.getPropertyIndex(prop)


    discard buff.uploadRune(scrSize, cursX, cursY, Glyph(rune: Rune'_', properties: propInd), 0)


  if rendered:
    if buff.dirtiedColors:
      buff.colors[].copyTo buff.colorSsbo[]
      buff.dirtiedColors = false

    buff.fontTarget.model.reuploadSsbo()
  buff.frameBuffer.clearColor = buff.properties.background

proc shapeId(shape: Shape): uint32 =
  shape.kind.ord.uint32 shl (31u16 - 4u16)  # We use 3 bits for all of our shapes, 1 for "isWhiteSpace"

proc offsetPos(pos, size, scrSize: Vec2): Vec2 =
  vec2(
    -1f + (pos.x - size.x / 2) / scrSize.x,
    1f - (pos.y + size.y / 2) / scrSize.y
  )

proc uploadShape(buff: var Buffer, scrSize: Vec2, shape: Shape, ind: int): bool =
  let prop = buff.cachedProperties[int shape.props]
  let scrSize = scrSize / 2
  result = buff.propIsVisible(prop)
  if result:
    let
      theFg = buff.getColorIndex(prop.foreground)
      theBg = buff.getColorIndex(prop.background)
      shapeSize =
        case range[Rectangle..OutlineEllipse](shape.kind)
        of Rectangle, OutlineRectangle:
          vec2(shape.rectW, shape.rectH)
        of Ellipse, OutlineEllipse:
          vec2(shape.eRadius1, shape.eRadius2)
      size = shapeSize / scrSize
      calcPos = vec2(shape.x, shape.y).offsetPos(shapeSize, scrSize)
      x = calcPos.x
      y = calcPos.y

    let
      sineOffset = sin((buff.time + x) * prop.sineSpeed) * prop.sineStrength / scrSize.y
      shakeOffsetX =
        if prop.shakeStrength > 0:
          buff.noise.evaluate((buff.time + x * ind.float) * prop.shakeSpeed, float32 ind) * prop.shakeStrength / scrSize.y
        else:
          0
      shakeOffsetY =
        if prop.shakeStrength > 0:
          buff.noise.evaluate((buff.time + y * ind.float) * prop.shakeSpeed, float32 ind) * prop.shakeStrength / scrSize.y
        else:
          0

      xyzr = vec4(x + shakeOffsetX, y + sineOffset + shakeOffsetY, 0, 0)
      wh = vec4(size.x, size.y, 0, 0)

    buff.fontTarget.model.push FontRenderObj(
      fg: theFg,
      bg: theBg,
      fontIndex: shape.shapeId,
      xyzr: xyzr,
      wh: wh
      )

proc uploadGraphicsMode(buff: var Buffer, screenSize: Vec2) =
  assert buff.mode == Graphics
  let scrSize =
    if buff.useFrameBuffer:
      vec2(buff.pixelWidth.float32, buff.pixelHeight.float32)
    else:
      screenSize

  buff.fontTarget.model.clear()
  var rendered: bool
  for i, shape in buff.shapes.pairs:
    case shape.kind
    of Character:
      rendered = buff.uploadRune(
        scrSize, -1 + (shape.x / scrSize.x) * 2,
        1 - (shape.y / scrSize.y) * 2,
        Glyph(rune: shape.rune, properties: shape.props),
        i,
        shape.scale,
        offset = true
      )[0] or rendered
    of Rectangle, OutlineRectangle, Ellipse, OutlineEllipse:
      rendered = buff.uploadShape(scrSize, shape, i) or rendered

    else:
      discard

  if rendered:
    if buff.dirtiedColors:
      buff.colors[].copyTo buff.colorSsbo[]
      buff.dirtiedColors = false

    buff.fontTarget.model.reuploadSsbo()

proc upload*(buff: var Buffer, dt: float32, screenSize: Vec2) =
  buff.time += dt
  case buff.mode
  of Text:
    buff.uploadTextMode(screenSize, dt)
  of Graphics:
    buff.uploadGraphicsMode(screenSize)

proc render*(buff: Buffer) =
  buff.textShader.reloadIfneeded()
  buff.graphicShader.reloadIfneeded()

  var old: (Glint, Glint, GlSizeI, GlSizeI)
  if buff.useFrameBuffer:
    glGetIntegerv(GlViewPort, old[0].addr)
    glViewport(0, 0, buff.pixelWidth, buff.pixelHeight)
    buff.frameBuffer.clear()
    buff.frameBuffer.bindBuffer()
  buff.colorSsbo[].bindBuffer(1)
  buff.atlas.ssbo.bindBuffer(2)


  case buff.mode
  of Text:
    buff.textShader.makeActive()
    buff.textShader.setUniform("fontTex", buff.atlas.texture)

  of Graphics:
    buff.graphicShader.makeActive()
    buff.graphicShader.setUniform("fontTex", buff.atlas.texture, false)

  glEnable(GlBlend)
  glBlendFunc(GlOne, GlOneMinusSrcAlpha)

  buff.fontTarget.model.render()
  glDisable(GlBlend)

  Shader(Gluint(0)).makeActive()

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

proc newLine*(buff: var Buffer, moveCamera = true) =
  assert buff.mode == Text
  buff.lines.add Line()
  inc buff.cursorY
  buff.cursorX = 0
  if moveCamera and buff.cursorY - buff.cameraPos >= buff.lineHeight:
    buff.cameraPos = buff.lines.len - buff.lineHeight

iterator chr*(s: string): Rune =
  for rune in s.runes:
    yield rune

iterator chr*(s: openarray[Glyph]): Glyph =
  for glyph in s.items:
    yield glyph

proc isNewLine(rune: Rune): bool = rune == Rune '\n'
proc isNewLine(glyph: Glyph): bool = glyph.rune.isNewLine()


proc put*(buffer: var Buffer, line: var Line, s: string | openArray[Glyph], props: GlyphProperties, start: int = 0): int =
  when s is string:
    let propIndex = buffer.getPropertyIndex(props)
    for i, rune in enumerate s.runes:
      let runeInd =
        if buffer.groupPrint:
          inc buffer.groupIndex
          buffer.groupIndex
        else:
          i

      line.glyphs[start + result] = Glyph(rune: rune, properties: propIndex, timeToDisplay: runeInd.float32 * props.displaySpeed)
      inc result
  else:
    line.glyphs[start .. s.high + start] = s


proc put*(buffer: var Buffer, line: var Line, s: string | openArray[Glyph], start: int = 0): int =
  buffer.put(line, s, buffer.properties, start)

proc shouldTicker*(buffer: Buffer, line: Line, len, width: int): bool =
  if width == -1:
    len - 1 > buffer.lineWidth - buffer.cursorX
  elif len < width:
    false
  else:
    for i in width..len:
      if not line.glyphs[i].rune.isWhiteSpace():
        return true
    false

proc ticker*(buffer: Buffer, line: var Line, progress: float32, len: var int, width = -1) =
  ## Tickers the line, if width is supplied trims whitespace from the right side
  let
    high = len - 1
    offset =
      if width == -1:
        min(high, buffer.lineWidth - buffer.cursorX - 1)
      else:
        width
  if width != -1:
    len = offset

  if buffer.shouldTicker(line, len, width):


    let startIndex = int((high.float32) + progress) mod high

    if startIndex == 0:
      return

    var temp = line
    let
      endIndex = clamp(startIndex + offset, startIndex, high)
      sliceEnd = endIndex - startIndex
      remaining = offset - sliceEnd
    line.glyphs[0 .. sliceEnd] = temp.glyphs[startIndex..endIndex]
    line.glyphs[sliceEnd + 1 ..  sliceEnd + 1 + remaining] = temp.glyphs[0 .. remaining]

proc put*(buff: var Buffer, s: string | openarray[Glyph], props: GlyphProperties, moveCamera = true, wrapped = false, getBuffer: static bool = false): auto =
  ## `moveCamera` indicates whether the camera should move when messages go off screenSize
  ## `wrapped` means that instead of writting in deadspace a newline will be inserted
  ## `getBuffer` indicates whether to return the data written over
  assert buff.mode == Text
  when getBuffer:
    result = newSeq[Glyph]()

  if buff.lines.len == 0:
    buff.lines.add Line()

  let propInd = buff.getPropertyIndex(props)

  for i, rune in enumerate s.chr:
    when getBuffer:
      result.add buff.lines[buff.cursorY].glyphs[buff.cursorX]

    let runeInd =
      if buff.groupPrint:
        inc buff.groupIndex
        buff.groupIndex
      else:
        i

    if rune.isNewLine():
      buff.newLine(moveCamera)
    else:
      if wrapped and buff.cursorX + 1 > buff.lineWidth:
        buff.newLine()

      if buff.cursorX < buff.lineWidth:
        buff.lines[buff.cursorY].glyphs[buff.cursorX] =
          when rune is Rune:
            Glyph(rune: rune, properties: propInd, timeToDisplay: runeInd.float32 * props.displaySpeed)
          else:
            rune

        inc buff.cursorX

  if moveCamera and buff.cursorY - buff.cameraPos >= buff.lineHeight:
    buff.cameraPos = buff.lines.len - buff.lineHeight

proc put*(buff: var Buffer, line: Line, len: int, moveCamera = true, wrapped = false, getBuffer: static bool = false): auto =
  buff.put(line.glyphs.toOpenArray(0, len - 1), buff.properties, moveCamera, wrapped, getBuffer)


proc put*(buff: var Buffer, s: string, moveCamera = true, wrapped = false) =
  put buff, s, buff.properties, moveCamera, wrapped

proc put*(buff: var Buffer, s: seq[Glyph], props: GlyphProperties, moveCamera = true, wrapped = false, getBuffer: static bool = false) = # `seq[Glyph]` != openArray
  buff.put(s.toOpenArray(0, s.high), props, moveCamera, wrapped, getBuffer)

proc put*(buff: var Buffer, s: seq[Glyph], moveCamera = true, wrapped = false) =
  put buff, s, buff.properties, moveCamera, wrapped

proc drawText*(buff: var Buffer, s: string, x, y, rot, scale: float32, props: GlyphProperties) =
  assert buff.mode == Graphics
  let propInd = buff.getPropertyIndex(props)

  var (x, y) = (x, y)
  for rune in s.runes:
    buff.shapes.add Shape(
      x: x,
      y: y,
      kind: Character,
      rune: rune,
      props: propInd,
      scale: scale,
    )
    let rune = # Whitespace should not be drawn empty
      if rune.isWhiteSpace():
        Rune('+')
      else:
        rune
    let entry = buff.atlas[].runeEntry(rune)
    x += entry.rect.w * scale / 2

proc drawText*(buff: var Buffer, s: string, x, y, rot, scale: float32) =
  buff.drawText(s, x, y, rot, scale, buff.properties)

proc drawText*(buff: var Buffer, s: string, x, y: float32) =
  buff.drawText(s, x, y, 0, 1, buff.properties)

proc drawRect*(buff: var Buffer, x, y, width, height: float32, props: GlyphProperties, outline = false) =
  let propInd = buff.getPropertyIndex(props)
  buff.shapes.add:
    if outline:
      Shape(kind: OutlineRectangle, x: x, y: y, rectW: width, rectH: height, props: propInd)
    else:
      Shape(kind: Rectangle, x: x, y: y, rectW: width, rectH: height, props: propInd)

proc drawRect*(buff: var Buffer, x, y, width, height: float32, outline = false) =
  buff.drawRect(x, y, width, height, buff.properties, outline)

proc drawBox*(buff: var Buffer, x, y, width: float32, props: GlyphProperties, outline = false) =
  buff.drawRect(x, y, width, width, props, outline)

proc drawBox*(buff: var Buffer, x, y, width: float32, outline = false) =
  buff.drawRect(x, y, width, width, buff.properties, outline)

proc drawEllipse*(buff: var Buffer, x, y, majorRadius, minorRadius: float32, props: GlyphProperties, outline = false) =
  let propInd = buff.getPropertyIndex(props)

  buff.shapes.add:
    if outline:
      Shape(kind: OutlineEllipse, x: x, y: y, eRadius1: minorRadius, eRadius2: majorRadius, props: propInd)
    else:
      Shape(kind: Ellipse, x: x, y: y, eRadius1: minorRadius, eRadius2: majorRadius, props: propInd)

proc drawEllipse*(buff: var Buffer, x, y, majorRadius, minorRadius: float32, outline = false) =
  buff.drawEllipse(x, y, majorRadius, minorRadius, buff.properties, outline)

proc drawCircle*(buff: var Buffer, x, y, radius: float32, props: GlyphProperties, outline = false) =
  buff.drawEllipse(x, y, radius, radius, props, outline)

proc drawCircle*(buff: var Buffer, x, y, radius: float32, outline = false) =
  buff.drawEllipse(x, y, radius, radius, buff.properties, outline)

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

proc getPosition*(buff: Buffer): (int, int) =
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

proc showCursor*(buffer: var Buffer, offset: int) =
  buffer.graphicCursorX = buffer.cursorX + offset
  buffer.graphicCursorY = buffer.cursorY

proc hideCursor*(buffer: var Buffer) =
  buffer.graphicCursorX = -1
  buffer.graphicCursorY = -1

when isMainModule:
  import texttables, styledtexts
  const clear = color(0, 0, 0, 0)
  var
    buff = Buffer(lineWidth: 40, lineHeight: 40, properties: GlyphProperties(foreground: parseHtmlColor"White", background: clear))
    fontPath = "../PublicPixel.ttf"

  proc init(truss: var Truss) =
    buff.initResources(fontPath, seedNoise = false)
    truss.inputs.startTextInput(default(inputs.Rect), "")
    buff.put("hello world!", GlyphProperties(foreground: parseHtmlColor"Green", background: parseHtmlColor"Yellow", sineSpeed: 5f, sineStrength: 10f))
    buff.put(" bleh \n\n", GlyphProperties(foreground: parseHtmlColor"Green"))
    buff.put("\nHello travllllllerrrrs", GlyphProperties(foreground: parseHtmlColor"Purple", background: parseHtmlColor"Beige", shakeSpeed: 5f, shakeStrength: 10f))
    buff.put("\n" & "―".repeat(30), GlyphProperties(foreground: parseHtmlColor"Red", blinkSpeed: 5f))
    buff.put("\n" & "―".repeat(30), GlyphProperties(foreground: parseHtmlColor"White", blinkSpeed: 1f))
    buff.newLine()

    type
      MyEntry = object
        a {.tableName: styledText"<text foreground=red sineStrength=10 sineSpeed=4>Test</text> yes", tableAlign: alignLeft.}: int
        b: int
    var a = [MyEntry(a: 100, b: 200), MyEntry(a: 100, b: 200), MyEntry(a: 100, b: 200)]
    buff.printTable(a)
    buff.put("\n>")

  var textScale = 1f

  proc update(truss: var Truss, dt: float32) =
    if buff.mode == Text:
      if isTextInputActive():
        if truss.inputs.inputText().len > 0:
          buff.put truss.inputs.inputText()
          truss.inputs.setInputText("")
        if truss.inputs.isDownRepeating(KeyCodeReturn):
          buff.put("\n>")
      if truss.inputs.isDownRepeating(KeyCodeUp):
        buff.scrollUp()
      if truss.inputs.isDownRepeating(KeyCodeDown):
        buff.scrollDown()

      if truss.inputs.isDownRepeating(KeyCodeInsert):
        buff.mode = Graphics
    else:
      buff.shapes.setLen(0)
      buff.drawBox(10, 10, 10, GlyphProperties(foreground: parseHtmlColor"Orange", blinkSpeed: 4f))
      buff.drawBox(20, 20, 100, GlyphProperties(foreground: parseHtmlColor"White"))
      buff.drawBox(30, 30, 80, GlyphProperties(foreground: parseHtmlColor"Blue", shakeStrength: 5f, shakeSpeed: 4f))
      buff.drawBox(120, 10, 10, GlyphProperties(foreground: parseHtmlColor"Orange", blinkSpeed: 4f))
      buff.drawBox(10, 120, 10, GlyphProperties(foreground: parseHtmlColor"Orange", blinkSpeed: 4f))
      buff.drawBox(120, 120, 10, GlyphProperties(foreground: parseHtmlColor"Orange", blinkSpeed: 4f))

      let
        scaledX = truss.inputs.getMousePos().x.float32
        scaledY = truss.inputs.getMousePos().y.float32

      buff.drawText("Hello", scaledX, scaledY, 0, textScale, GlyphProperties(foreground: parseHtmlColor"Blue", shakeStrength: 5f, shakeSpeed: 4f))
      textScale += truss.inputs.getMouseScroll().float32 * 10 * dt

      if truss.inputs.isDownRepeating(KeyCodeInsert):
        buff.mode = Text

    buff.upload(dt, truss.windowSize.vec2)

  proc draw(truss: var Truss) =
    buff.render()
  var truss = Truss.init("Something", ivec2(1280, 720), init, update, draw, vsync = true, flags = {})
  while truss.isRunning:
    truss.update()
