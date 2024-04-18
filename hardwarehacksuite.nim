import screenrenderer, texttables
import pkg/chroma
import pkg/truss3D/inputs
import std/[algorithm, strutils, math]

type
  HackGuess = object
    id {.tableName: "Id".}: int
    password {.tableName: "Password".}: string
    timeToDeny {.tableName:"Time To Deny".}: int
    guessed {.tableName: "Guessed".}: bool

  HardwareHack* = object
    target: string
    actualPassword: string
    currentGuessInd: int
    guesses: seq[HackGuess]
    hackTime: float32
    currentChar: int
    input: string
    errorMsg: string
    hackSpeed: float32 = 1

proc isInit*(hwHack: HardwareHack): bool = hwHack.target != ""

proc closeness(guess: HackGuess): float32 =
  ## An incorrect character takes 1 second to deny, a correct one takes 2 to acceept
  ## So if the password is `hunter2` and the guessed password is `hunte2r` it takes 11s of the 14s expected
  guess.timeToDeny / guess.password.len * 2

proc init*(_: typedesc[HardwareHack], securityLevel, actualPassPos: int, target, password: string, hackSpeed = 1f): HardwareHack =
  result = HardwareHack(target: target, actualPassword: password, currentGuessInd: -1, hackSpeed: hackSpeed)
  var sortedPass = password
  while result.guesses.len < securityLevel:
    if result.guesses.len == actualPassPos:
      result.guesses.add HackGuess(id: result.guesses.len, password: password)
    else:
      if sortedPass.nextPermutation and sortedPass != password:
        result.guesses.add HackGuess(id: result.guesses.len, password: sortedPass)

proc currentGuess(hwHack: HardwareHack): lent HackGuess = hwHack.guesses[hwHack.currentGuessInd]
proc currentGuess(hwHack: var HardwareHack): var HackGuess = hwHack.guesses[hwHack.currentGuessInd]

proc isHacking(hwHack: HardwareHack): bool =
  hwHack.currentGuessInd != -1 and not hwHack.currentGuess.guessed



proc update*(hwHack: var HardwareHack, dt: float32, active: bool) =
  if active and not hwHack.isHacking:
    if inputText().len > 0:
      hwHack.input.add inputText()
    if KeyCodeReturn.isDownRepeating:
      try:
        let guess = parseInt(hwHack.input)
        if guess in 0..hwHack.guesses.high:
          hwHack.currentGuessInd = guess
        else:
          hwHack.errorMsg = "$# is not in range $#" % [$guess, $(0..hwHack.guesses.high)]
      except CatchableError as e:
        # TODO: Replace with i8n: "Expected integer"
        hwHack.errorMsg = e.msg
      hwHack.hackTime = 0
      hwHack.input = ""
      hwHack.currentChar = 0

  if KeyCodeBackspace.isDownRepeating and hwHack.input.len > 0:
    hwHack.input.setLen(hwHack.input.high)

  if hwHack.isHacking:
    hwHack.hackTime = clamp(hwHack.hackTime + dt * hwHack.hackSpeed, 0, hwHack.actualPassword.len.float32 * 2)

    let flooredTime = floor(hwHack.hackTime - hwHack.currentChar.float32 * 2)

    if flooredTime == 1:
      if hwHack.currentGuess.password[hwHack.currentChar] != hwHack.actualPassword[hwHack.currentChar]:
        hwHack.currentGuess.guessed = true
        hwHack.currentGuess.timeToDeny = hwHack.hackTime.round().int
    if flooredTime == 2:
      inc hwHack.currentChar

    if hwHack.currentChar == hwHack.actualPassword.len:
      hwHack.currentGuess.guessed = true
      hwHack.currentGuess.timeToDeny = hwHack.actualPassword.len * 2
      assert hwHack.currentGuess.timeToDeny == hwHack.hackTime.round().int # Some sanity

proc put*(buffer: var Buffer, hwHack: HardwareHack) =
  var entryProps {.global.}: seq[GlyphProperties]
  entryProps.setLen(0)
  for guess in hwHack.guesses:
    entryProps.add buffer.properties
    entryProps.add:
      if guess.guessed: # password, time, guessed
        [GlyphProperties(foreground: mix(parseHtmlColor("red"), parseHtmlColor("green"), guess.closeness)),
        GlyphProperties(foreground: parseHtmlColor"green"), GlyphProperties(foreground: parseHtmlColor"green")]
      else:
        [buffer.properties, buffer.properties, GlyphProperties(foreground: parseHtmlColor"red")]
  buffer.printTable(hwHack.guesses, entryProperties = entryProps)
  if hwHack.isHacking:
    buffer.put "["
    let progress = int (hwHack.hackTime / (hwHack.actualPassword.len.float32 * 2)) * 10
    buffer.put "=".repeat(progress)
    buffer.put " ".repeat(10 - progress)
    buffer.put "]"

  if not hwHack.isHacking:
    buffer.put "Id to guess: "
    buffer.put hwHack.input
    if hwHack.errorMsg.len > 0:
      buffer.newLine()
      buffer.put hwHack.errorMsg, GlyphProperties(foreground: parseHtmlColor("red"))

  buffer.newLine()


