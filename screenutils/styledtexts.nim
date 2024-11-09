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

import std/[options, xmltree, xmlparser, parsexml, strutils, strtabs, unicode]
import screenrenderer

type
  Fragment* = object
    msg*: string
    case usesRaw: bool
    of false:
      modifiedProps*: StringTableRef
    else:
      props: GlyphProperties

  StyledText* = object
    len*: int # Number of printed characters not length of string
    fragments*: seq[Fragment]

proc clone(table: StringTableRef): StringTableRef =
  result = newStringTable()
  if table != nil:
    result[] = table[]

proc addFragment(node: XmlNode, text: var StyledText, property: StringTableRef) =
  case node.kind
  of xnElement:
    var properties: StringTableRef

    for name, field in GlyphProperties().fieldPairs:
      if (let attrVal = node.attr(name); attrVal != ""):
        if properties == nil:
          properties = property.clone()
        properties[name] = attrVal

    for node in node:
      node.addFragment(text, properties)

  of xnText:
    text.fragments.add Fragment(msg: node.text, usesRaw: false, modifiedProps: property)
    text.len += node.text.runeLen
  else:
    discard


proc styledText*(s: string): StyledText =
  var s = s
  if not s.endsWith("</text>"):
    s = "<text>" & s & "</text>"
  let xml = s.parseXml({allowEmptyAttribs, allowUnquotedAttribs, reportWhitespace})
  xml.addFragment(result, nil)

proc styledText*(s: string, props: GlyphProperties): StyledText =
  StyledText(len: s.runeLen, fragments: @[Fragment(msg: s, usesRaw: true, props: props)])

proc styledText*(fragments: openArray[(string, GlyphProperties)]): StyledText =
  for (msg, prop) in fragments:
    result.len += msg.runeLen
    result.fragments.add Fragment(msg: msg, usesRaw: true, props: prop)

proc add*(result: var StyledText, toAdd: sink StyledText) =
  result.len += toAdd.len
  result.fragments.add ensureMove toAdd.fragments


proc add*(result: var StyledText, toAdd: sink string) =
  result.add styledText(toAdd)


proc put*(buff: var Buffer, s: StyledText, moveCamera = true, wrapped = false, modifier: proc(_: var GlyphProperties) = nil) =
  for frag in s.fragments:
    let msg {.cursor.} = frag.msg
    var props: GlyphProperties

    if frag.usesRaw:
      props = frag.props

    else:
      props = buff.properties
      if frag.modifiedProps != nil:
        for prop, val in frag.modifiedProps:
          for name, field in props.fieldPairs:
            if name == prop:
              when field is Color:
                field = parseHtmlColor(val)
              elif field is float32:
                field = parseFloat(val).float32
    if modifier != nil:
      modifier(props)

    buff.put(msg, props, moveCamera, wrapped)



proc putToLine*(buff: var Buffer, s: StyledText, modifier: proc(_: var GlyphProperties) = nil): (Line, int) =
  for frag in s.fragments:
    let msg {.cursor.} = frag.msg
    var props: GlyphProperties

    if frag.usesRaw:
      props = frag.props

    else:
      props = buff.properties
      if frag.modifiedProps != nil:
        for prop, val in frag.modifiedProps:
          for name, field in props.fieldPairs:
            if name == prop:
              when field is Color:
                field = parseHtmlColor(val)
              elif field is float32:
                field = parseFloat(val).float32
    if modifier != nil:
      modifier(props)
    result[1] += buff.put(result[0], msg, props, result[1])
