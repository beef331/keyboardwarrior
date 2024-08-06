import std/os

quit execShellCmd("nim c -d:testing -d:release -o:rendertest -r keyboardwarrior.nim")

