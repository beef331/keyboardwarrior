import ../screenutils/texttables
import pkg/truss3D/inputs
import std/[algorithm, strutils, math, random, sets]
import gamestates

type
  HackGuess = object
    id {.tableName: "Id".}: int
    password {.tableName: "Password".}: string
    timeToDeny {.tableName:"Time To Deny".}: int
    guessed {.tableName: "Guessed".}: bool

  HardwareHack* = object
    name: string
    target: string
    actualPassword: string
    currentGuessInd: int
    guesses: seq[HackGuess]
    hackTime: float32
    timeToHack: float32
    currentChar: int
    input: string
    errorMsg: string
    hackSpeed: float32 = 1

proc isInit*(hwHack: HardwareHack): bool = hwHack.target != ""

proc closeness(guess: HackGuess): float32 =
  ## An incorrect character takes 1 second to deny, a correct one takes 2 to acceept
  ## So if the password is `hunter2` and the guessed password is `hunte2r` it takes 11s of the 14s expected
  1f - (guess.timeToDeny - guess.password.len) / (guess.password.len * 2)

proc init*(_: typedesc[HardwareHack], securityLevel, actualPassPos: int, target, password: string, hackSpeed = 1f): HardwareHack =
  result = HardwareHack(name: "hhs" & target, target: target, actualPassword: password, currentGuessInd: -1, hackSpeed: hackSpeed)
  var
    sortedPass = password
    added: HashSet[string]

  while result.guesses.len < securityLevel:
    sortedPass.shuffle()
    if result.guesses.len == actualPassPos:
      result.guesses.add HackGuess(id: result.guesses.len, password: password)
      added.incl password
    elif sortedPass != password and sortedPass notin added:
      result.guesses.add HackGuess(id: result.guesses.len, password: sortedPass)
      added.incl sortedPass

proc currentGuess(hwHack: HardwareHack): lent HackGuess = hwHack.guesses[hwHack.currentGuessInd]
proc currentGuess(hwHack: var HardwareHack): var HackGuess = hwHack.guesses[hwHack.currentGuessInd]

proc isHacking(hwHack: HardwareHack): bool =
  hwHack.currentGuessInd != -1 and not hwHack.currentGuess.guessed

proc put*(buffer: var Buffer, hwHack: HardwareHack) =
  var entryProps {.global.}: seq[GlyphProperties]
  entryProps.setLen(0)
  for guess in hwHack.guesses:
    entryProps.add buffer.properties
    entryProps.add:
      if guess.guessed: # password, time, guessed
        let mixedColor = GlyphProperties(foreground: mix(parseHtmlColor("red"), parseHtmlColor("lime"), guess.closeness))
        [mixedColor, mixedColor, GlyphProperties(foreground: parseHtmlColor"lime")]
      else:
        [buffer.properties, buffer.properties, GlyphProperties(foreground: parseHtmlColor"red")]
  buffer.printTable(hwHack.guesses, entryProperties = entryProps)
  if hwHack.isHacking:
    buffer.put "["
    let progress = int (hwHack.hackTime / hwHack.timeToHack) * 10
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

proc update*(hwHack: var HardwareHack, gameState: var GameState, dt: float32, active: bool) =
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
      if hwHack.isHacking:
        var totalHackTime = 0f
        for i, ch in hwHack.currentGuess.password:
          if ch == hwHack.actualPassword[i]:
            totalHackTime += 1f
          elif (i < hwHack.actualPassword.high and hwHack.actualPassword[i + 1] == ch) or (i > 0 and  hwHack.actualPassword[i-1] == ch):
            totalHackTime += 2f
          else:
            totalHackTime += 3f
        hwHack.timeToHack = totalHackTime

  if KeyCodeBackspace.isDownRepeating and hwHack.input.len > 0:
    hwHack.input.setLen(hwHack.input.high)

  if hwHack.isHacking:
    hwHack.hackTime = clamp(hwHack.hackTime + dt * hwHack.hackSpeed, 0, hwHack.timeToHack)
    if hwHack.hackTime >= hwHack.timeToHack:
      hwHack.currentGuess.guessed = true
      hwHack.currentGuess.timeToDeny = int(hwHack.timeToHack)

  if active:
    gameState.buffer.put(hwHack)

proc onExit*(hw: var HardwareHack, gameState: GameState) = discard
proc name*(hw: HardwareHack): string = hw.name

proc hhs(gamestate: var GameState, input: string) =
  if gameState.hasProgram("hhs"):
    gameState.enterProgram("hhs")
  else:
    randomize()
    var password = newString(5)
    for ch in password.mitems:
      ch = sample(Digits + Letters)
    gameState.enterProgram(HardwareHack.init(20, rand(0..10), "Orion", password, 3).toTrait(Program))

command(
  "hhs",
  "This starts a hack on the target.",
  hhs
)
