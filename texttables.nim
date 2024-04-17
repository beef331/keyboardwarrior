import std/private/asciitables
import std/[parseutils, strutils, options, macros]
import screenrenderer

template tableName*(s: string){.pragma.}

proc paramCount(T: typedesc[object or tuple]): int =
  for _ in default(T).fields:
    inc result

proc tableFormat*(val: auto): string = $val

type
  TableKind* = enum
    NewLine
    Seperator
    Entry
  TableFormatProps* = object
    intSigDigs*: int
    floatSigDigs*: int

iterator tableEntries[T](
  values: openArray[T],
  defaultProperties, headerProperties: GlyphProperties,
  entryProperties: openArray[GlyphProperties],
  formatProperties: TableFormatProps
  ): tuple[msg: string, props: GlyphProperties, kind: TableKind] =
  var
    strings = newSeqOfCap[(string, GlyphProperties)](values.len * T.paramCount)
    largest = newSeq[int](T.paramCount)

  var fieldInd = 0
  for name, field in default(T).fieldPairs:
    let nameStr =
      when field.hasCustomPragma(tableName):
        field.getCustomPragmaVal(tableName)
      else:
        name

    largest[fieldInd] = nameStr.len
    strings.add (nameStr, headerProperties)
    inc fieldInd

  var entryInd = 0
  for entry in values:
    fieldInd = 0
    for field in entry.fields:
      let str =
        when field is SomeFloat:
          if formatProperties.floatSigDigs > 0:
            field.formatFloat(precision = formatProperties.floatSigDigs)
          else:
            $field
        elif field is SomeInteger:
          if formatProperties.intSigDigs > 0:
            field.float.formatFloat(precision = formatProperties.intSigDigs)
          else:
            $field
        else:
          $field


      strings.add:
        if entryInd < entryProperties.len:
          (str, entryProperties[entryInd])
        else:
          (str, defaultProperties)
      largest[fieldInd] = max(strings[^1][0].len, largest[fieldInd])
      inc entryInd
      inc fieldInd

  for i, entry in strings:
    yield (entry[0].alignLeft(largest[i mod T.paramCount]), entry[1], Entry)
    if (i + 1) mod T.paramCount == 0:
      yield ("", defaultProperties, NewLine)
    else:
      yield ("", entry[1], Seperator)



proc printTable*[T: object or tuple](
  buffer: var Buffer,
  table: openArray[T],
  headerProperties = none(GlyphProperties),
  entryProperties: openArray[GlyphProperties] = @[],
  formatProperties = TableFormatProps()
) =
  for str, props, kind in table.tableEntries(buffer.properties, headerProperties.get(buffer.properties), entryProperties, formatProperties):
    case kind
    of Entry:
      buffer.put(str, props)
    of NewLine:
      buffer.newLine()
    of Seperator:
      buffer.put("|")
