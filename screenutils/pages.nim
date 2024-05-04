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

import screenrenderer, texttables

proc printPaged*[T: object or tuple](
  buffer: var Buffer,
  table: openArray[T],
  selected: int
  headerProperties = none(GlyphProperties),
  entryProperties: openArray[GlyphProperties] = @[],
  formatProperties = TableFormatProps()
) =
  var line = 0
  for str, props, kind in table.tableEntries(buffer.properties, headerProperties.get(buffer.properties), entryProperties, formatProperties):
    case kind
    of Entry:
      buffer.put(str, props)
    of NewLine:
      buffer.newLine()
      if line == selected:
        buffer.put ">"
      else:
        buffer.put " "
      inc line
    of Seperator:
      buffer.put("|")
