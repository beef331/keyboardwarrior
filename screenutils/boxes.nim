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
