import "$projectdir"/screenutils/screenrenderer
import std/[enumerate, macros, strutils, typetraits]
import "$projectdir"/screenutils/[styledtexts, texttables, progressbars]
import pkg/[truss3D, chroma]


template title*(name: string) {.pragma.}
template name*(name: StyledText) {.pragma.}
template increment*(val: auto) {.pragma.}



type
  UserOptions* = object
    selected*: int


    curveAmount* {.title: "Customization", increment: 0.06.}: range[0f..1f] = 0
    bloomAmount* {.increment: 0.06.}: range[0f..1f] = 0
    volume* {.increment: 0.05.}: range[0f..1f] = 0.1

    screenR* {.title: "Foreground", increment: 3u8, name: styledText("Red", GlyphProperties(foreground: parseHtmlColor"Red")).}: range[0u8..255u8] = 255u8
    screenG* {.increment: 3u8, name: styledText("Green", GlyphProperties(foreground: parseHtmlColor"Green")).}: range[0u8..255u8] = 255u8
    screenB* {.increment: 3u8, name: styledText("Blue", GlyphProperties(foreground: parseHtmlColor"Blue")).}: range[0u8..255u8] = 255u8

    backgroundR* {.title: "Background", increment: 3u8, name: styledText("Red", GlyphProperties(foreground: parseHtmlColor"Red")).}: range[0u8..255u8] = 0u8
    backgroundG* {.increment: 3u8, name: styledText("Green", GlyphProperties(foreground: parseHtmlColor"Green")).}: range[0u8..255u8] = 0u8
    backgroundB* {.increment: 3u8, name: styledText("Blue", GlyphProperties(foreground: parseHtmlColor"Blue")).}: range[0u8..255u8] = 0u8


