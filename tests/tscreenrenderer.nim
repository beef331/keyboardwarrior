import ../screenutils/[pam, screenrenderer, texttables]
import pkg/[truss3D, opengl, vmath, pixie]
import pkg/pixie/fileformats/png
import std/[os, strutils]

const clear = color(0, 0, 0, 0)
var
  buffer = Buffer(lineWidth: 40, lineHeight: 40, properties: GlyphProperties(foreground: parseHtmlColor"White", background: clear))
  fontPath = "../PublicPixel.ttf"
  errorCode = 0

template genTest(name: string, dt: float32, body: untyped) =

  buffer.clearTo(0)
  buffer.properties.background = color(0, 0, 0, 1)
  body
  buffer.upload(dt)
  buffer.render()

  var img = newImage(buffer.pixelWidth, buffer.pixelHeight)

  glGetTextureImage(buffer.getFrameBufferTexture().Gluint, 0, GlRgba,  GlUnsignedByte, img.data.len * 4, img.data[0].addr)
  img.flipVertical()
  let
    path = "testimages" / name.changeFileExt("png")
    testPath = path.changeFileExt("test.png")
    debugPath = path.changeFileExt("debug.png")
  if not fileExists(path):
    img.writeFile(path)
  else:
    if not compare(ImageComparison(data: path, isPath: true), ImageComparison(data: img.encodePng()), 0.0001, debugPath):
      img.writeFile(testPath)
      echo "Error: Failed to match ", name
      errorCode = 1


proc init =
  buffer.initResources(fontPath, true, false)
  buffer.setFontSize 30
  genTest("basictest", 3):
    buffer.put("This is a test\n")
    buffer.put("Hello\n\n", GlyphProperties(foreground: parseHtmlColor"red"))
    buffer.put("Hello\n\n", GlyphProperties(foreground: parseHtmlColor"orange", sinestrength: 10f, sineSpeed: 10))
    buffer.put("Hello\n", GlyphProperties(foreground: parseHtmlColor"cyan", shakeSpeed: 10f, shakeStrength: 10))

  genTest("tables", 0):
    var data: seq[tuple[name: string, age: int, favouritePet: string]] = @[
      ("Jimbo", 23, "Dog"),
      ("Jeana", 25, "All Dogs"),
      ("Gene", 32, "Cat"),
      ("Steve", 17, "Really all Dogs"),
      ("Ira", 21, "Cat")
    ]

    var props: seq[GlyphProperties]
    for person in data:
      props.add buffer.properties
      props.add:
        if person.age > 30:
          GlyphProperties(foreground: parseHtmlColor"yellow", background: parseHtmlColor"#0f0f0f")
        else:
          GlyphProperties(foreground: parseHtmlColor"green", background: parseHtmlColor"#010101")
      props.add:
        if "Dog" in person.favouritePet:
          GlyphProperties(foreground: parseHtmlColor"green")
        else:
          GlyphProperties(foreground: parseHtmlColor("red"))
    buffer.printTable(data, entryProperties = props)

  quit errorCode

proc update(dt: float32) = discard


proc draw = discard


initTruss("Something", ivec2(800, 600), init, update, draw, flags = {})
