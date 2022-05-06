from illwave as iw import `[]`, `[]=`, `==`
from wavecorepkg/wavescript import nil
from strutils import format
from sequtils import nil
from ansiutils/codes import stripCodes
from unicode import nil
from paramidi import nil
from ./midi import nil
from times import nil
from ./sound import nil
from os import nil
from ./constants import nil
from json import nil
from ./storage import nil
from wavecorepkg/common import nil
from parseutils import nil
import tables, sets
from wavecorepkg/client import nil
import unicode
from terminal import nil

type
  RefStrings* = ref seq[ref string]

proc splitLines*(text: string): RefStrings =
  new result
  var row = 0
  for line in strutils.splitLines(text):
    var s: ref string
    new s
    s[] = codes.dedupeCodes(line)
    result[].add(s)
    # make sure the line is UTF-8
    let col = unicode.validateUtf8(line)
    if col != -1:
      raise newException(Exception, "Invalid UTF-8 data in line $1, byte $2".format(row+1, col+1))
    row.inc

proc isWhitespace(ch: Rune): bool =
  unicode.isWhitespace(ch) or ($ch in wavescript.whitespaceChars)

proc wrapLine(line: string, maxWidth: int): seq[string] =
  # never wrap lines that are a command or that start with a whitespace char
  let
    chars = line.toRunes
    firstValidChar = codes.firstValidChar(chars)
  if firstValidChar == -1 or ($chars[firstValidChar] == "/" or $chars[firstValidChar] in wavescript.whitespaceChars):
    return @[line]
  elif chars.stripCodes.len <= maxWidth:
    return @[line]

  var
    partitions: seq[tuple[isWhitespace: bool, chars: seq[Rune]]]
    lastPartition: tuple[isWhitespace: bool, chars: seq[Rune]]
  for ch in runes(line):
    if lastPartition.chars.len == 0:
      lastPartition = (isWhitespace(ch), @[ch])
    else:
      let isWhitespace = isWhitespace(ch)
      if isWhitespace == lastPartition.isWhitespace:
        lastPartition.chars.add ch
      else:
        partitions.add lastPartition
        lastPartition = (isWhitespace, @[ch])
  partitions.add lastPartition
  var currentLine: seq[Rune]
  for (isWhitespace, chars) in partitions:
    if isWhitespace:
      currentLine &= chars
    else:
      let currLen = currentLine.stripCodes.len
      if currLen == 0 or currLen + chars.stripCodes.len <= maxWidth:
        currentLine &= chars
      else:
        result.add $currentLine
        currentLine = chars
  result.add $currentLine

type
  LineRange = tuple[lineNum: int, startCol: int, endCol: int]
  LineRanges = seq[LineRange]
  ToWrappedTable* = TableRef[int, LineRanges]
  ToUnwrappedTable* = TableRef[int, LineRange]

proc wrapLines*(lines: RefStrings): tuple[lines: RefStrings, toWrapped: ToWrappedTable, toUnwrapped: ToUnwrappedTable] =
  new result.lines
  new result.toWrapped
  new result.toUnwrapped
  var
    wrappedLineNum = 0
    lineNum = 0
  for line in lines[]:
    let newLines = wrapLine(line[], constants.editorWidth)
    if newLines.len == 1:
      result.lines[].add(line)
      let endCol = line[].stripCodes.runeLen
      result.toWrapped[lineNum] = @[(wrappedLineNum, 0, endCol)]
      result.toUnwrapped[wrappedLineNum] = (lineNum, 0, endCol)
      wrappedLineNum.inc
      lineNum.inc
    else:
      var
        col = 0
        ranges: LineRanges
      for newLine in newLines:
        var s: ref string
        new s
        s[] = newLine
        result.lines[].add(s)
        let
          # at the very end of the line, there is an extra spot
          # so the cursor can append to the end
          adjust = if newLines.len - ranges.len == 1: 0 else: -1
          endCol = col+newLine.stripCodes.runeLen + adjust
        ranges.add((wrappedLineNum, col, endCol))
        result.toUnwrapped[wrappedLineNum] = (lineNum, col, endCol)
        wrappedLineNum.inc
        col += newLine.stripCodes.runeLen
      result.toWrapped[lineNum] = ranges
      lineNum.inc

proc wrapLines*(lines: seq[string]): seq[string] =
  for line in lines:
    let newLines = wrapLine(line, constants.editorWidth)
    if newLines.len == 1:
      result.add(line)
    else:
      for newLine in newLines:
        result.add(newLine)

proc joinLines*(lines: RefStrings): string =
  let lineCount = lines[].len
  var i = 0
  for line in lines[]:
    result &= line[]
    if i != lineCount - 1:
      result &= "\n"
    i.inc

proc animateLines*(lines: seq[string], startTime: float): seq[string] =
  const totalSecs = 0.4
  let lineCount = int(lines.len.float * min(1f, (times.epochTime() - startTime) / totalSecs))
  result = lines
  if lineCount < lines.len:
    let offset = int(float(constants.editorWidth) * (1f - (lineCount.float / lines.len.float)))
    for i in 0 ..< lineCount:
      result[i] = result[i].stripCodes
      if i mod 2 == 0:
        let line = result[i] & strutils.repeat(' ', constants.editorWidth)
        result[i] = line[offset ..< line.len]
      else:
        result[i] = strutils.repeat(' ', offset) & result[i]
    for i in lineCount ..< lines.len:
      result[i] = ""

proc addClear(s: ref string) =
  if s[].len == 0 or not strutils.startsWith(s[], "\e[0"):
    s[] = codes.dedupeCodes("\e[0m" & s[])

proc add*(lines: var RefStrings, line: string) =
  var s: ref string
  new s
  s[] = line
  s.addClear
  lines[].add(s)

proc set*(lines: var RefStrings, i: int, line: string) =
  var s: ref string
  new s
  s[] = line
  s.addClear
  lines[i] = s

proc drafts*(): seq[string] =
  for filename in storage.list():
    if strutils.endsWith(filename, ".new") or strutils.endsWith(filename, ".edit"):
      result.add(filename)

proc recents*(pubKey: string): seq[string] =
  for filename in storage.list():
    if strutils.endsWith(filename, ".ansiwave") and
        # don't include banner in recents
        filename != pubKey & ".ansiwave":
      result.add(filename)

type
  CommandTreesRef* = ref seq[wavescript.CommandTree]

proc linesToTrees*(lines: seq[string] | seq[ref string]): seq[wavescript.CommandTree] =
  var scriptContext = waveScript.initContext()
  let
    cmds = wavescript.extract(sequtils.map(lines, codes.stripCodesIfCommand))
    treesTemp = sequtils.map(cmds, proc (text: auto): wavescript.CommandTree = wavescript.parse(scriptContext, text))
  wavescript.parseOperatorCommands(treesTemp)

proc play*(events: seq[paramidi.Event]): midi.PlayResult =
  if iw.gIllwaveInitialized:
    let
      midiResult = midi.play(events)
      (secs, playResult) = midiResult
      startTime = times.epochTime()
    if playResult.kind == sound.Error:
      return midiResult
    var tb = iw.newTerminalBuffer(terminal.terminalWidth(), terminal.terminalHeight())
    while true:
      let currTime = times.epochTime() - startTime
      if currTime > secs:
        break
      iw.fill(tb, 0, 0, constants.editorWidth + 1, 2, " ")
      iw.fill(tb, 0, 0, int((currTime / secs) * float(constants.editorWidth + 1)), 0, "▓")
      iw.write(tb, 0, 1, "press esc to stop playing")
      iw.display(tb)
      let key = iw.getKey()
      if key in {iw.Key.Tab, iw.Key.Escape}:
        break
      os.sleep(constants.sleepMsecs)
    midi.stop(playResult.addrs)
    return midiResult
  else:
    let currentTime = times.epochTime()
    return midi.play(events)

proc compileAndPlayAll*(trees: seq[wavescript.CommandTree]): midi.PlayResult =
  var
    noErrors = true
    nodes = json.JsonNode(kind: json.JArray)
    midiContext = paramidi.initContext()
  for cmd in trees:
    if cmd.kind != wavescript.Valid or cmd.skip:
      continue
    let
      res =
        try:
          let node = wavescript.toJson(cmd)
          nodes.elems.add(node)
          midi.compileScore(midiContext, node, false)
        except Exception as e:
          midi.CompileResult(kind: midi.Error, message: e.msg)
    case res.kind:
    of midi.Valid:
      discard
    of midi.Error:
      noErrors = false
      break
  if noErrors:
    midiContext = paramidi.initContext()
    let res =
      try:
        midi.compileScore(midiContext, nodes, true)
      except Exception as e:
        midi.CompileResult(kind: midi.Error, message: e.msg)
    case res.kind:
    of midi.Valid:
      if res.events.len > 0:
        return play(res.events)
    of midi.Error:
      discard

type
  ParsedKind* = enum
    Local, Remote, Error,
  Parsed* = object
    case kind*: ParsedKind
    of Local, Remote:
      key*: string
      sig*: string
      target*: string
      time*: string
      content*: string
    of Error:
      discard

proc parseAnsiwave*(ansiwave: string, parsed: var Parsed) =
  try:
    let
      (commands, headersAndContent, content) = common.parseAnsiwave(ansiwave)
      key = commands["/key"]
      sig = commands["/sig"]
      target = commands["/target"]
      time = commands["/time"]
    parsed.key = key
    parsed.sig = sig
    parsed.target = target
    parsed.time = time
    parsed.content = content
  except Exception as ex:
    parsed = Parsed(kind: Error)

proc getTime*(parsed: Parsed): int =
  try:
    discard parseutils.parseInt(parsed.time, result)
  except Exception as ex:
    discard

proc getFromLocalOrRemote*(response: client.Result[client.Response], sig: string): Parsed =
  let local = storage.get(sig & ".ansiwave")

  # if both failed, return error
  if local == "" and response.kind == client.Error:
    return Parsed(kind: Error)

  var
    localParsed: Parsed
    remoteParsed: Parsed

  # parse local
  if local == "":
    localParsed = Parsed(kind: Error)
  else:
    localParsed = Parsed(kind: Local)
    parseAnsiwave(local, localParsed)

  # parse remote
  if response.kind == client.Error:
    remoteParsed = Parsed(kind: Error)
  else:
    remoteParsed = Parsed(kind: Remote)
    parseAnsiwave(response.valid.body, remoteParsed)

  # if both parsed successfully, compare their timestamps and use the later one
  if localParsed.kind != Error and remoteParsed.kind != Error:
    if localParsed.getTime > remoteParsed.getTime:
      localParsed
    else:
      remoteParsed
  elif localParsed.kind != Error:
    localParsed
  else:
    remoteParsed

