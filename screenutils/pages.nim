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
