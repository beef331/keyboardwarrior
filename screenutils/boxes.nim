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

import screenrenderer
import std/[options, strutils]
export options

type BoxBorder* = enum
  None
  Outline
  Spaces

proc longestLine(strs: openArray[string]): int =
  for val in strs:
    result = max(val.len, result)


proc drawBox*(
  buffer: var Buffer,
  messages: openArray[string],
  properties: openArray[GlyphProperties] = @[],
  borderProperties = none(GlyphProperties),
  border = BoxBorder.None
) =

  var (x, y) = buffer.getPosition()

  let
    borderProperties = borderProperties.get(buffer.properties)
    lineLength = longestLine(messages)
  case border
  of Outline:
    buffer.put "+", borderProperties
    buffer.put "-".repeat(lineLength), borderProperties
    buffer.put "+", borderProperties
  of Spaces:
    buffer.put " ".repeat(lineLength + 2), borderProperties
  else:
    discard

  inc y


  for i, msg in messages:
    buffer.setPosition(x, y)

    let prop =
      if i < properties.high:
        properties[i]
      else:
        buffer.properties

    case border
    of Outline:
      buffer.put "|", borderProperties
    of Spaces:
      buffer.put " ", borderProperties
    else:
      discard

    buffer.put msg.center(lineLength), prop

    case border
    of Outline:
      buffer.put "|", borderProperties
    of Spaces:
      buffer.put " ", borderProperties
    else:
      discard
    inc y

  buffer.setPosition(x, y)

  case border
  of Outline:
    buffer.put "+", borderProperties
    buffer.put "-".repeat(lineLength), borderProperties
    buffer.put "+", borderProperties
  of Spaces:
    buffer.put " ".repeat(lineLength + 2), borderProperties
  else:
    discard
