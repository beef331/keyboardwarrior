# Package

version = "0.1.0"
author        = "Jason Beetham"
description   = "TUI Combat and Trading simulator"
license       = "MIT"
srcDir        = ""
bin = @["keyboardwarrior"]


# Dependencies

requires "nim >= 2.0.0"
requires "https://github.com/beef331/truss3d >= 0.2.38"
requires "https://github.com/beef331/traitor >= 0.2.17"
requires "https://github.com/beef331/potato >= 0.1.2"
requires "opensimplexnoise >= 0.2.0"

task buildWindowsRelease, "Builds a windows release duhhhh":
  selfExec("c -d:mingw -d:strip -d:lto ./keyboardwarrior.nim")
