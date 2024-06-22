import pkg/truss3D/logging
import std/strutils

template todo*(s: string): untyped =
  let file = instantiationInfo(fullPaths = true)
  proc bleh() {.used.} = discard


  info("TODO: \e]8;;$#\e\\$#($#:$#)\e]8;;\e\\" % [
    file.fileName,
    file.fileName,
    $file.line,
    $file.column,
    s]
  )
