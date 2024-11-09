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
  if count > result.len:
    result.fragments.insert(Fragment(msg: padding.repeat(count - result.len)), 0)
    result.len = count

proc alignLeft*(s: StyledText, count: Natural, padding = ' '): StyledText =
  result = s
  result.fragments.add(Fragment(msg: padding.repeat(count - result.len)))
  result.len = count

type
  TableKind* = enum
    NewLine
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
  buffer: Buffer,
  seperator: string
  ): tuple[msg: StyledText, kind: TableKind] =

  let properties = buffer.properties
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
          let str =
            when field is StyledText:
              field
            else:
              $field


        strings.add:
          when str is StyledText:
            str
          else:
            StyledText(len: str.runeLen, fragments: @[Fragment(msg: str)])

        largest[fieldInd] = max(strings[^1].len, largest[fieldInd])
        inc entryInd
        inc fieldInd
  for i, entry in strings:
    let
      alignInd = i mod T.paramCount
      size = max(min(largest[alignInd], buffer.lineWidth - buffer.getPosition()[0]), 0)

    var entry = alignFunctions[alignInd](entry, size)

    yield (entry, Entry)
    if (i + 1) mod T.paramCount == 0:
      yield (styledText"", NewLine)
    else:
      yield (styledText seperator, Entry)



proc printTable*[T: object or tuple](
  buffer: var Buffer,
  table: openArray[T],
) =
  for str, kind in table.tableEntries(buffer, "|"):
    case kind
    of Entry:
      buffer.put(str)
    of NewLine:
      buffer.newLine()


proc printPaged*[T: object or tuple](
  buffer: var Buffer;
  table: openArray[T];
  selected: int = -1;
  seperator = "|";
  printHeader: bool = true;
  unselectedModifier: proc(prop: var GlyphProperties) = nil;
  selectedModifier: proc(prop: var GlyphProperties) = nil;
  tickerProgress = 0f32
) =
  var line = 0

  if selected != -1:
    buffer.put " " # Everything is offset

  let modifiers = [false: unselectedModifier, selectedModifier]
  for str, kind in table.tableEntries(buffer, seperator):
    if not printHeader and line == 0:
      if kind == NewLine:
        inc line
      continue
    case kind
    of Entry:
      let modifier = modifiers[selected + 1 == line]
      if tickerProgress == 0:
        buffer.put(str, modifier = modifier)
      else:
        var (line, len) =
          buffer.putToLine(str, modifier = modifier)
        if buffer.shouldTicker(len):
          var props = buffer.properties
          if modifier != nil:
            modifier(props)
          len += buffer.put(line, "][", props, len)
        buffer.ticker(line, tickerProgress, len)
        buffer.put(line.glyphs.toOpenArray(0, len - 1), buffer.properties)


    of NewLine:
      buffer.newLine()
      if selected != -1:
        if line == selected:
          buffer.put ">"
        else:
          buffer.put " "
      inc line
