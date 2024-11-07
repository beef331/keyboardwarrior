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

import std/[strutils, options, macros, sequtils, unicode, strbasics]
import screenrenderer, styledtexts

proc alignRight*(s: StyledText, count: Natural, padding = ' '): StyledText =
  result = s
  result.fragments.insert(Fragment(msg: padding.repeat(count - result.len)), 0)
  result.len = count

proc alignLeft*(s: StyledText, count: Natural, padding = ' '): StyledText =
  result = s
  result.fragments.add(Fragment(msg: padding.repeat(count - result.len)))
  result.len = count

type
  TableKind* = enum
    NewLine
    Seperator
    Entry
  AlignFunction* = proc(_: StyledText, _: Natural, padding: char): StyledText

template tableName*(s: string or StyledText){.pragma.}
template tableAlign*(_: AlignFunction){.pragma.}
template tableStringify*(p: proc {.nimcall.}){.pragma.}
template tableSkip*() {.pragma.}


proc paramCount(T: typedesc[object or tuple]): int =
  for field in default(T).fields:
    when not field.hasCustomPragma(tableSkip):
      inc result

proc toPrintedName(name: string): string =
  let firstCap = name.find({'A'..'Z'})
  if firstCap != -1:
    result = name.toOpenArray(0, firstCap - 1).capitalize()
  else:
    result = name.capitalize()

  var nd = firstCap
  while firstCap >= 0 and nd < name.high:
    var newInd = name.find({'A'..'Z'}, nd + 1)
    if newInd == -1:
      newInd = name.len

    result.add " "
    result.add name.toOpenArray(nd, newInd - 1)
    nd = newInd

iterator tableEntries*[T](
  values: openArray[T],
  properties: GlyphProperties
  ): tuple[msg: StyledText, kind: TableKind] =
  var
    strings = newSeqOfCap[StyledText](values.len * T.paramCount)
    largest = newSeq[int](T.paramCount)
    alignFunctions = newSeqWith(T.paramCount, alignRight)

  var fieldInd = 0
  for name, field in default(T).fieldPairs:
    when not field.hasCustomPragma(tableSkip):
      let nameStr =
        when field.hasCustomPragma(tableName):
          field.getCustomPragmaVal(tableName)[0]
        else:
          const val = static: name.toPrintedName()
          val

      when field.hasCustomPragma(tableAlign):
        alignFunctions[fieldInd] = field.getCustomPragmaVal(tableAlign)

      largest[fieldInd] = nameStr.len
      strings.add:
        when nameStr is StyledText:
          nameStr
        else:
          StyledText(len: nameStr.runeLen, fragments: @[Fragment(msg: nameStr)])
      inc fieldInd

  var entryInd = 0
  for entry in values:
    fieldInd = 0
    let obj = entry # TODO: `hasCustomPragma` bug that requires this
    for field in obj.fields:
      when not field.hasCustomPragma(tableSkip):
        when field.hasCustomPragma(tableStringify):
          let str = field.getCustomPragmaVal(tableStringify)[0](field)
        else:
          let str = $field


        strings.add:
          when str is StyledText:
            str
          else:
            StyledText(len: str.runeLen, fragments: @[Fragment(msg: str)])

        largest[fieldInd] = max(strings[^1].len, largest[fieldInd])
        inc entryInd
        inc fieldInd

  for i, entry in strings:
    let alignInd = i mod T.paramCount
    yield (alignFunctions[alignInd](entry, largest[alignInd]), Entry)
    if (i + 1) mod T.paramCount == 0:
      yield (styledText"", NewLine)
    else:
      yield (styledText"", Seperator)



proc printTable*[T: object or tuple](
  buffer: var Buffer,
  table: openArray[T],
) =
  for str, kind in table.tableEntries(buffer.properties):
    case kind
    of Entry:
      buffer.put(str)
    of NewLine:
      buffer.newLine()
    of Seperator:
      buffer.put("|")


proc printPaged*[T: object or tuple](
  buffer: var Buffer;
  table: openArray[T];
  selected: int = -1;
  printHeader: bool = true;
  unselectedModifier: proc(prop: var GlyphProperties) = nil;
  selectedModifier: proc(prop: var GlyphProperties) = nil;
) =
  var line = 0
  if selected != -1:
    buffer.put " " # Everything is offset
  for str, kind in table.tableEntries(buffer.properties):
    case kind
    of Entry:
      if not printHeader and line == 0:
        continue

      if selected + 1 == line:
        buffer.put(str, modifier = selectedModifier)
      else:
        buffer.put(str, modifier = unselectedModifier)
    of NewLine:
      buffer.newLine()
      if selected != -1:
        if line == selected:
          buffer.put ">"
        else:
          buffer.put " "
      inc line
    of Seperator:
      if not printHeader and line == 0:
        continue
      buffer.put("|")

