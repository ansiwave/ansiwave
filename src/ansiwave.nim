from illwill as iw import `[]`, `[]=`
import tables
import pararules
import unicode
from os import nil
from strutils import nil
from sequtils import nil
from sugar import nil
from times import nil
from ansiwavepkg/ansi import nil
from ansiwavepkg/wavescript import CommandTree
from ansiwavepkg/midi import nil
from ansiwavepkg/sound import nil
from paramidi import Context
from json import nil

const
  sleepMsecs = 10
  hintSecs = 5

proc exitClean(message: string) =
  iw.illwillDeinit()
  iw.showCursor()
  if message.len > 0:
    quit(message)
  else:
    quit(0)

proc exitClean() {.noconv.} =
  exitClean("")

proc parseCode(codes: var seq[string], ch: Rune): bool =
  proc terminated(s: string): bool =
    if s.len > 0:
      let lastChar = s[s.len - 1]
      return ansi.codeTerminators.contains(lastChar)
    else:
      return false
  let s = $ch
  if s == "\e":
    codes.add(s)
    return true
  elif codes.len > 0 and not codes[codes.len - 1].terminated:
    codes[codes.len - 1] &= s
    return true
  return false

proc dedupeParams(params: var seq[int]) =
  var i = params.len - 1
  while i > 0:
    let param = params[i]
    if param == 0:
      params = params[i ..< params.len]
      break
    elif param >= 30 and param <= 39:
      let prevParams = sequtils.filter(params[0 ..< i], proc (x: int): bool = not (x >= 30 and x <= 39))
      params = prevParams & params[i ..< params.len]
      i = prevParams.len - 1
    elif param >= 40 and param <= 49:
      let prevParams = sequtils.filter(params[0 ..< i], proc (x: int): bool = not (x >= 40 and x <= 49))
      params = prevParams & params[i ..< params.len]
      i = prevParams.len - 1
    else:
      i.dec

proc applyCode(tb: var iw.TerminalBuffer, code: string) =
  let trimmed = code[1 ..< code.len - 1]
  let params = ansi.parseParams(trimmed)
  for param in params:
    if param == 0:
      iw.setBackgroundColor(tb, iw.bgNone)
      iw.setForegroundColor(tb, iw.fgNone)
      iw.setStyle(tb, {})
    elif param >= 1 and param <= 9:
      var style = iw.getStyle(tb)
      style.incl(iw.Style(param))
      iw.setStyle(tb, style)
    elif param >= 30 and param <= 39:
      iw.setForegroundColor(tb, iw.ForegroundColor(param))
    elif param >= 40 and param <= 49:
      iw.setBackgroundColor(tb, iw.BackgroundColor(param))

proc writeAnsi(tb: var iw.TerminalBuffer, x, y: Natural, s: string) =
  var currX = x
  var codes: seq[string]
  for ch in runes(s):
    if parseCode(codes, ch):
      continue
    for code in codes:
      applyCode(tb, code)
    var c = iw.TerminalChar(ch: ch, fg: iw.getForegroundColor(tb), bg: iw.getBackgroundColor(tb),
                            style: iw.getStyle(tb))
    tb[currX, y] = c
    inc(currX)
    codes = @[]
  for code in codes:
    applyCode(tb, code)
  iw.setCursorXPos(tb, currX)
  iw.setCursorYPos(tb, y)

proc stripCodes(line: seq[Rune]): string =
  var codes: seq[string]
  for ch in line:
    if parseCode(codes, ch):
      continue
    result &= $ch

proc stripCodes(line: string): string =
  stripCodes(line.toRunes)

proc stripCodesIfCommand(line: ref string): string =
  var
    codes: seq[string]
    foundFirstValidChar = false
  for ch in runes(line[]):
    if parseCode(codes, ch):
      continue
    if not foundFirstValidChar and ch.toUTF8[0] != '/':
      return ""
    else:
      foundFirstValidChar = true
      result &= $ch

proc dedupeCodes*(line: seq[Rune]): string =
  var codes: seq[string]
  proc addCodes(res: var string) =
    var params: seq[int]
    for code in codes:
      if code[1] == '[' and code[code.len - 1] == 'm':
        let trimmed = code[1 ..< code.len - 1]
        params &= ansi.parseParams(trimmed)
      # this is some other kind of code that we should just preserve
      else:
        res &= code
    dedupeParams(params)
    if params.len > 0:
      res &= "\e[" & strutils.join(params, ";") & "m"
    codes = @[]
  for ch in line:
    if parseCode(codes, ch):
      continue
    elif codes.len > 0:
      addCodes(result)
    result &= $ch
  if codes.len > 0:
    addCodes(result)

proc dedupeCodes*(line: string): string =
  dedupeCodes(line.toRunes)

proc getRealX(line: seq[Rune], x: int): int =
  result = 0
  var fakeX = 0
  var codes: seq[string]
  for ch in line:
    if parseCode(codes, ch):
      result.inc
      continue
    if fakeX == x:
      break
    result.inc
    fakeX.inc

proc getParamsBeforeRealX(line: seq[Rune], realX: int): seq[int] =
  var codes: seq[string]
  for ch in line[0 ..< realX]:
    if parseCode(codes, ch):
      continue
  for code in codes:
    if code[1] == '[' and code[code.len - 1] == 'm':
      let trimmed = code[1 ..< code.len - 1]
      result &= ansi.parseParams(trimmed)
  dedupeParams(result)

proc getParamsBeforeRealX(line: string, realX: int): seq[int] =
  getParamsBeforeRealX(line.toRunes, realX)

proc firstValidChar(line: seq[Rune]): int =
  result = -1
  var realX = 0
  var codes: seq[string]
  for ch in line:
    if not parseCode(codes, ch):
      result = realX
      break
    realX.inc

proc deleteBefore(line: var seq[Rune], count: int) =
  var x = 0
  while x < count:
    var firstChar = line.firstValidChar
    if firstChar == -1:
      break
    line.delete(firstChar)
    x.inc

proc firstValidCharAfter(line: seq[Rune], count: int): int =
  result = -1
  var realX = 0
  var fakeX = 0
  var codes: seq[string]
  for ch in line:
    if not parseCode(codes, ch):
      if fakeX > count:
        result = realX
        break
      fakeX.inc
    realX.inc

proc deleteAfter(line: var seq[Rune], count: int) =
  var x = 0
  var codes: seq[string]
  var firstCharAfter = 0
  while firstCharAfter != -1:
    firstCharAfter = line.firstValidCharAfter(count)
    if firstCharAfter == -1:
      break
    line.delete(firstCharAfter)

type
  Id* = enum
    Global, TerminalWindow,
    Editor, Errors, Tutorial, Publish,
  Attr* = enum
    CursorX, CursorY,
    ScrollX, ScrollY,
    X, Y, Width, Height,
    SelectedBuffer, Lines,
    Editable, SelectedMode,
    SelectedChar, SelectedFgColor, SelectedBgColor,
    Prompt, ValidCommands, InvalidCommands, Links,
    HintText, HintTime,
  PromptKind = enum
    None, DeleteLine, StopPlaying,
  RefStrings = ref seq[ref string]
  RefCommands = ref seq[wavescript.CommandTree]
  Link = object
    icon: Rune
    callback: proc ()
    error: bool
  RefLinks = ref Table[int, Link]

schema Fact(Id, Attr):
  CursorX: int
  CursorY: int
  ScrollX: int
  ScrollY: int
  X: int
  Y: int
  Width: int
  Height: int
  SelectedBuffer: Id
  Lines: RefStrings
  Editable: bool
  SelectedMode: int
  SelectedChar: string
  SelectedFgColor: string
  SelectedBgColor: string
  Prompt: PromptKind
  ValidCommands: RefCommands
  InvalidCommands: RefCommands
  Links: RefLinks
  HintText: string
  HintTime: float

proc splitLines(text: string): RefStrings =
  new result
  for line in strutils.splitLines(text):
    var s: ref string
    new s
    s[] = line
    result[].add(s)

proc add(lines: var RefStrings, line: string) =
  var s: ref string
  new s
  s[] = line
  lines[].add(s)

proc set(lines: var RefStrings, i: int, line: string) =
  var s: ref string
  new s
  s[] = line
  lines[i] = s

proc getCurrentLine(bufferId: int): int
proc moveCursor(bufferId: int, x: int, y: int)
proc tick*(): iw.TerminalBuffer

proc play(events: seq[paramidi.Event], bufferId: int, bufferWidth: int, lineTimes: seq[tuple[line: int, time: float]]) =
  if events.len == 0:
    return
  var
    tb = tick()
    lineTimesIdx = -1
  iw.display(tb)
  let
    (secs, playResult) = midi.play(events)
    startTime = times.epochTime()
  if playResult.kind == sound.Error:
    exitClean(playResult.message)
  while true:
    let currTime = times.epochTime() - startTime
    if currTime > secs:
      break
    # go to the right line
    if lineTimesIdx + 1 < lineTimes.len:
      let (line, time) = lineTimes[lineTimesIdx + 1]
      if currTime >= time:
        lineTimesIdx.inc
        moveCursor(bufferId, 0, line)
        tb = tick()
    # draw progress bar
    iw.fill(tb, 0, 0, bufferWidth + 1, if bufferId == Editor.ord: 1 else: 0, " ")
    iw.fill(tb, 0, 0, int((currTime / secs) * float(bufferWidth + 1)), 0, "▓")
    iw.display(tb)
    let key = iw.getKey()
    if key == iw.Key.Tab:
      break
    os.sleep(sleepMsecs)
  midi.stop(playResult.addrs)

proc setErrorLink(session: var auto, linksRef: RefLinks, cmdLine: int, errLine: int) =
  var sess = session
  let cb =
    proc () =
      sess.insert(Global, SelectedBuffer, Errors)
      sess.insert(Errors, CursorX, 0)
      sess.insert(Errors, CursorY, errLine)
  linksRef[cmdLine] = Link(icon: "!".runeAt(0), callback: cb, error: true)

proc setRuntimeError(session: var auto, cmdsRef: RefCommands, errsRef: RefCommands, linksRef: RefLinks, bufferId: int, line: int, message: string) =
  var cmdIndex = -1
  for i in 0 ..< cmdsRef[].len:
    if cmdsRef[0].line == line:
      cmdIndex = i
      break
  if cmdIndex >= 0:
    cmdsRef[].delete(cmdIndex)
    session.insert(bufferId, ValidCommands, cmdsRef)
  var errIndex = -1
  for i in 0 ..< errsRef[].len:
    if errsRef[0].line == line:
      errIndex = i
      break
  if errIndex >= 0:
    errsRef[].delete(errIndex)
  setErrorLink(session, linksRef, line, errsRef[].len)
  errsRef[].add(wavescript.CommandTree(kind: wavescript.Error, line: line, message: message))
  session.insert(bufferId, InvalidCommands, errsRef)
  session.insert(bufferId, Links, linksRef)
  if getCurrentLine(bufferId) != line:
    session.insert(bufferId, CursorX, 0)
    session.insert(bufferId, CursorY, line)

proc compileAndPlayAll(session: var auto, buffer: tuple) =
  session.insert(buffer.id, Prompt, StopPlaying)
  var
    noErrors = true
    nodes = json.JsonNode(kind: json.JArray)
    lineTimes: seq[tuple[line: int, time: float]]
    context = paramidi.initContext()
    lastTime = 0.0
  for cmd in buffer.commands[]:
    if cmd.skip:
      continue
    let
      res =
        try:
          let node = wavescript.toJson(cmd)
          nodes.elems.add(node)
          midi.compileScore(context, node, false)
        except Exception as e:
          midi.CompileResult(kind: midi.Error, message: e.msg)
    case res.kind:
    of midi.Valid:
      lineTimes.add((cmd.line, lastTime))
      lastTime = context.seconds
    of midi.Error:
      setRuntimeError(session, buffer.commands, buffer.errors, buffer.links, buffer.id, cmd.line, res.message)
      noErrors = false
      break
  if noErrors:
    context = paramidi.initContext()
    let res =
      try:
        midi.compileScore(context, nodes, true)
      except Exception as e:
        midi.CompileResult(kind: midi.Error, message: e.msg)
    case res.kind:
    of midi.Valid:
      play(res.events, buffer.id, buffer.width, lineTimes)
    of midi.Error:
      discard
  session.insert(buffer.id, Prompt, None)

let rules =
  ruleset:
    rule getGlobals(Fact):
      what:
        (Global, SelectedBuffer, selectedBuffer)
        (Global, HintText, hintText)
        (Global, HintTime, hintTime)
    rule getTerminalWindow(Fact):
      what:
        (TerminalWindow, Width, windowWidth)
        (TerminalWindow, Height, windowHeight)
    rule updateBufferSize(Fact):
      what:
        (TerminalWindow, Width, width)
        (TerminalWindow, Height, height)
        (id, Y, bufferY, then = false)
      then:
        session.insert(id, Width, min(width - 2, 80))
        session.insert(id, Height, height - 3 - bufferY)
    rule updateTerminalScrollX(Fact):
      what:
        (id, Width, bufferWidth)
        (id, CursorX, cursorX)
        (id, ScrollX, scrollX, then = false)
      cond:
        cursorX >= 0
      then:
        let scrollRight = scrollX + bufferWidth - 1
        if cursorX < scrollX:
          session.insert(id, ScrollX, cursorX)
        elif cursorX > scrollRight:
          session.insert(id, ScrollX, scrollX + (cursorX - scrollRight))
    rule updateTerminalScrollY(Fact):
      what:
        (id, Height, bufferHeight)
        (id, CursorY, cursorY)
        (id, Lines, lines)
        (id, ScrollY, scrollY, then = false)
      cond:
        cursorY >= 0
      then:
        let scrollBottom = scrollY + bufferHeight - 1
        if cursorY < scrollY:
          session.insert(id, ScrollY, cursorY)
        elif cursorY > scrollBottom and cursorY < lines[].len:
          session.insert(id, ScrollY, scrollY + (cursorY - scrollBottom))
    rule cursorChanged(Fact):
      what:
        (id, CursorX, cursorX)
        (id, CursorY, cursorY)
        (id, Lines, lines, then = false)
      then:
        if lines[].len == 0:
          if cursorX != 0:
            session.insert(id, CursorX, 0)
          if cursorY != 0:
            session.insert(id, CursorY, 0)
          return
        if cursorY < 0:
          session.insert(id, CursorY, 0)
        elif cursorY >= lines[].len:
          session.insert(id, CursorY, lines[].len - 1)
        else:
          if cursorX > lines[cursorY][].stripCodes.runeLen:
            session.insert(id, CursorX, lines[cursorY][].stripCodes.runeLen)
          elif cursorX < 0:
            session.insert(id, CursorX, 0)
    rule addClearToBeginningOfEveryLine(Fact):
      what:
        (id, Lines, lines)
      then:
        var shouldInsert = false
        for i in 0 ..< lines[].len:
          if lines[i][].len == 0 or not strutils.startsWith(lines[i][], "\e[0"):
            lines[i][] = dedupeCodes("\e[0m" & lines[i][])
            shouldInsert = true
        if shouldInsert:
          session.insert(id, Lines, lines)
    rule parseCommands(Fact):
      what:
        (id, Lines, lines)
        (id, Width, width)
      cond:
        id != Errors.ord
      then:
        let
          cmds = wavescript.parse(sequtils.map(lines[], stripCodesIfCommand))
          trees = wavescript.parseOperatorCommands(sequtils.map(cmds, wavescript.parse))
        var cmdsRef, errsRef: RefCommands
        var linksRef: RefLinks
        new cmdsRef
        new errsRef
        new linksRef
        var
          sess = session
          context = paramidi.initContext()
        for tree in trees:
          case tree.kind:
          of wavescript.Valid:
            # set the play button in the gutter to play the line
            let treeLocal = tree
            sugar.capture treeLocal, context:
              let
                cb =
                  proc () =
                    sess.insert(id, Prompt, StopPlaying)
                    var ctx = context
                    ctx.time = 0
                    new ctx.events
                    let res =
                      try:
                        midi.compileScore(ctx, wavescript.toJson(treeLocal), true)
                      except Exception as e:
                        midi.CompileResult(kind: midi.Error, message: e.msg)
                    case res.kind:
                    of midi.Valid:
                      play(res.events, id, width, @[])
                    of midi.Error:
                      setRuntimeError(sess, cmdsRef, errsRef, linksRef, id, treeLocal.line, res.message)
                    sess.insert(id, Prompt, None)
              linksRef[treeLocal.line] = Link(icon: "♫".runeAt(0), callback: cb)
            cmdsRef[].add(tree)
            # compile the line so the context object updates
            # this is important so attributes changed by previous lines
            # affect the play button
            try:
              discard paramidi.compile(context, wavescript.toJson(tree))
            except:
              discard
          of wavescript.Error:
            if id == Editor.ord:
              setErrorLink(sess, linksRef, tree.line, errsRef[].len)
              errsRef[].add(tree)
        session.insert(id, ValidCommands, cmdsRef)
        session.insert(id, InvalidCommands, errsRef)
        session.insert(id, Links, linksRef)
    rule updateErrors(Fact):
      what:
        (Editor, InvalidCommands, errors)
      then:
        var newLines: RefStrings
        var linksRef: RefLinks
        new newLines
        new linksRef
        for error in errors[]:
          var sess = session
          let line = error.line
          sugar.capture line:
            let cb =
              proc () =
                sess.insert(Global, SelectedBuffer, Editor)
                sess.insert(Editor, SelectedMode, 0) # force it to be write mode so the cursor is visible
                if getCurrentLine(Editor.ord) != line:
                  sess.insert(Editor, CursorX, 0)
                  sess.insert(Editor, CursorY, line)
            linksRef[newLines[].len] = Link(icon: "!".runeAt(0), callback: cb, error: true)
          newLines.add(error.message)
        session.insert(Errors, Lines, newLines)
        session.insert(Errors, CursorX, 0)
        session.insert(Errors, CursorY, 0)
        session.insert(Errors, ValidCommands, cast[RefCommands](nil))
        session.insert(Errors, InvalidCommands, cast[RefCommands](nil))
        session.insert(Errors, Links, linksRef)
    rule getBuffer(Fact):
      what:
        (id, CursorX, cursorX)
        (id, CursorY, cursorY)
        (id, ScrollX, scrollX)
        (id, ScrollY, scrollY)
        (id, Lines, lines)
        (id, X, x)
        (id, Y, y)
        (id, Width, width)
        (id, Height, height)
        (id, Editable, editable)
        (id, SelectedMode, mode)
        (id, SelectedChar, selectedChar)
        (id, SelectedFgColor, selectedFgColor)
        (id, SelectedBgColor, selectedBgColor)
        (id, Prompt, prompt)
        (id, ValidCommands, commands)
        (id, InvalidCommands, errors)
        (id, Links, links)

var session* = initSession(Fact, autoFire = false)

proc getCurrentLine(bufferId: int): int =
  session.query(rules.getBuffer, id = bufferId).cursorY

proc moveCursor(bufferId: int, x: int, y: int) =
  session.insert(bufferId, CursorX, x)
  session.insert(bufferId, CursorY, y)
  session.fireRules

proc onWindowResize(width: int, height: int) =
  session.insert(TerminalWindow, Width, width)
  session.insert(TerminalWindow, Height, height)

proc insertBuffer(id: Id, x: int, y: int, editable: bool, text: string) =
  session.insert(id, CursorX, 0)
  session.insert(id, CursorY, 0)
  session.insert(id, ScrollX, 0)
  session.insert(id, ScrollY, 0)
  session.insert(id, Lines, text.splitLines)
  session.insert(id, X, x)
  session.insert(id, Y, y)
  session.insert(id, Width, 0)
  session.insert(id, Height, 0)
  session.insert(id, Editable, editable)
  session.insert(id, SelectedMode, 0)
  session.insert(id, SelectedChar, "█")
  session.insert(id, SelectedFgColor, "")
  session.insert(id, SelectedBgColor, "")
  session.insert(id, Prompt, None)

proc setCursor(tb: var iw.TerminalBuffer, col: int, row: int) =
  if col < 0 or row < 0:
    return
  var ch = tb[col, row]
  ch.bg = iw.bgYellow
  if ch.fg == iw.fgYellow:
    ch.fg = iw.fgWhite
  elif $ch.ch == "█":
    ch.fg = iw.fgYellow
  tb[col, row] = ch
  iw.setCursorPos(tb, col, row)

proc onInput(key: iw.Key, buffer: tuple): bool =
  case key:
  of iw.Key.Backspace:
    if not buffer.editable:
      return false
    if buffer.cursorX == 0:
      session.insert(buffer.id, Prompt, DeleteLine)
    elif buffer.cursorX > 0:
      let
        line = buffer.lines[buffer.cursorY][].toRunes
        realX = getRealX(line, buffer.cursorX - 1)
        newLine = dedupeCodes($line[0 ..< realX] & $line[realX + 1 ..< line.len])
      var newLines = buffer.lines
      newLines.set(buffer.cursorY, newLine)
      session.insert(buffer.id, Lines, newLines)
      session.insert(buffer.id, CursorX, buffer.cursorX - 1)
  of iw.Key.Delete:
    if not buffer.editable:
      return false
    if buffer.cursorX == buffer.lines[buffer.cursorY][].stripCodes.runeLen:
      session.insert(buffer.id, Prompt, DeleteLine)
    elif buffer.cursorX < buffer.lines[buffer.cursorY][].stripCodes.runeLen:
      let
        line = buffer.lines[buffer.cursorY][].toRunes
        realX = getRealX(line, buffer.cursorX)
        newLine = dedupeCodes($line[0 ..< realX] & $line[realX + 1 ..< line.len])
      var newLines = buffer.lines
      newLines.set(buffer.cursorY, newLine)
      session.insert(buffer.id, Lines, newLines)
  of iw.Key.Enter:
    if not buffer.editable:
      return false
    let
      line = buffer.lines[buffer.cursorY][].toRunes
      realX = getRealX(line, buffer.cursorX)
      prefix = "\e[" & strutils.join(@[0] & getParamsBeforeRealX(line, realX), ";") & "m"
      before = line[0 ..< realX]
      after = line[realX ..< line.len]
    var newLines: RefStrings
    new newLines
    newLines[] = buffer.lines[][0 ..< buffer.cursorY]
    newLines.add($before)
    newLines.add(prefix & $after)
    newLines[].add(buffer.lines[][buffer.cursorY + 1 ..< buffer.lines[].len])
    session.insert(buffer.id, Lines, newLines)
    session.insert(buffer.id, CursorX, 0)
    session.insert(buffer.id, CursorY, buffer.cursorY + 1)
  of iw.Key.Up:
    session.insert(buffer.id, CursorY, buffer.cursorY - 1)
  of iw.Key.Down:
    session.insert(buffer.id, CursorY, buffer.cursorY + 1)
  of iw.Key.Left:
    session.insert(buffer.id, CursorX, buffer.cursorX - 1)
  of iw.Key.Right:
    session.insert(buffer.id, CursorX, buffer.cursorX + 1)
  of iw.Key.Home:
    session.insert(buffer.id, CursorX, 0)
  of iw.Key.End:
    session.insert(buffer.id, CursorX, buffer.lines[buffer.cursorY][].stripCodes.runeLen)
  of iw.Key.Tab:
    if buffer.prompt == DeleteLine:
      var newLines = buffer.lines
      if newLines[].len == 1:
        newLines.set(0, "")
      else:
        newLines[].delete(buffer.cursorY)
      session.insert(buffer.id, Lines, newLines)
      if buffer.cursorY > newLines[].len - 1:
        session.insert(buffer.id, CursorY, newLines[].len - 1)
  else:
    return false
  true

proc makePrefix(buffer: tuple): string =
  if buffer.selectedFgColor == "" and buffer.selectedBgColor != "":
    result = "\e[0m" & buffer.selectedBgColor
  elif buffer.selectedFgColor != "" and buffer.selectedBgColor == "":
    result = "\e[0m" & buffer.selectedFgColor
  elif buffer.selectedFgColor == "" and buffer.selectedBgColor == "":
    result = "\e[0m"
  elif buffer.selectedFgColor != "" and buffer.selectedBgColor != "":
    result = buffer.selectedFgColor & buffer.selectedBgColor

proc onInput(code: int, buffer: tuple): bool =
  if code < 32:
    return false
  let ch =
    try:
      char(code)
    except:
      return false
  if not buffer.editable:
    return false
  let
    line = buffer.lines[buffer.cursorY][].toRunes
    realX = getRealX(line, buffer.cursorX)
    prefix = buffer.makePrefix
    suffix = "\e[" & strutils.join(@[0] & getParamsBeforeRealX(line, realX), ";") & "m"
    chColored = prefix & $ch & suffix
    newLine = dedupeCodes($line[0 ..< realX] & chColored & $line[realX ..< line.len])
  var newLines = buffer.lines
  newLines.set(buffer.cursorY, newLine)
  session.insert(buffer.id, Lines, newLines)
  session.insert(buffer.id, CursorX, buffer.cursorX + 1)
  true

proc renderBuffer(tb: var iw.TerminalBuffer, buffer: tuple, key: iw.Key) =
  let focused = buffer.prompt != StopPlaying
  iw.drawRect(tb, buffer.x, buffer.y, buffer.x + buffer.width + 1, buffer.y + buffer.height + 1, doubleStyle = focused)

  let
    lines = buffer.lines[]
    scrollX = buffer.scrollX
    scrollY = buffer.scrollY
  var screenLine = 0
  for i in scrollY ..< lines.len:
    if screenLine > buffer.height - 1:
      break
    var line = lines[i][].toRunes
    line = line[0 ..< lines[i][].runeLen]
    if scrollX < line.stripCodes.runeLen:
      if scrollX > 0:
        deleteBefore(line, scrollX)
    else:
      line = @[]
    deleteAfter(line, buffer.width - 1)
    writeAnsi(tb, buffer.x + 1, buffer.y + 1 + screenLine, $line)
    if buffer.prompt != StopPlaying:
      # press gutter button with mouse or Tab
      if buffer.links[].contains(i):
        let linkY = buffer.y + 1 + screenLine
        iw.write(tb, buffer.x, linkY, $buffer.links[i].icon)
        if key == iw.Key.Mouse:
          let info = iw.getMouse()
          if info.button == iw.MouseButton.mbLeft and info.action == iw.MouseButtonAction.mbaPressed:
            if info.x == buffer.x and info.y == linkY:
              session.insert(buffer.id, CursorX, 0)
              session.insert(buffer.id, CursorY, i)
              let hintText =
                if buffer.links[i].error:
                  if buffer.id == Editor.ord:
                    "Hint: see the error with Tab"
                  elif buffer.id == Errors.ord:
                    "Hint: see where the error happened with Tab"
                  else:
                    ""
                else:
                  "Hint: play the current line with Tab"
              session.insert(Global, HintText, hintText)
              session.insert(Global, HintTime, times.epochTime() + hintSecs)
              buffer.links[i].callback()
        elif i == buffer.cursorY and key == iw.Key.Tab and buffer.prompt == None:
          buffer.links[i].callback()
    screenLine += 1

  if key == iw.Key.Mouse:
    let info = iw.getMouse()
    if info.button == iw.MouseButton.mbLeft and info.action == iw.MouseButtonAction.mbaPressed:
      session.insert(buffer.id, Prompt, None)
      if info.x >= buffer.x and
          info.x <= buffer.x + buffer.width and
          info.y >= buffer.y and
          info.y <= buffer.y + buffer.height:
        if buffer.mode == 0:
            session.insert(buffer.id, CursorX, info.x - (buffer.x + 1 - buffer.scrollX))
            session.insert(buffer.id, CursorY, info.y - (buffer.y + 1 - buffer.scrollY))
        elif buffer.mode == 1:
          let
            x = info.x - buffer.x - 1 + buffer.scrollX
            y = info.y - buffer.y - 1 + buffer.scrollY
          if x >= 0 and y >= 0:
            var lines = buffer.lines
            while y > lines[].len - 1:
              lines.add("")
            var line = lines[y][].toRunes
            while x > line.stripCodes.runeLen - 1:
              line.add(" ".runeAt(0))
            let realX = getRealX(line, x)
            line[realX] = buffer.selectedChar.runeAt(0)
            let prefix = buffer.makePrefix
            let suffix = "\e[" & strutils.join(@[0] & getParamsBeforeRealX(line, realX), ";") & "m"
            lines.set(y, dedupeCodes($line[0 ..< realX] & prefix & buffer.selectedChar & suffix & $line[realX + 1 ..< line.len]))
            session.insert(buffer.id, Lines, lines)
  elif focused and buffer.mode == 0:
    if key != iw.Key.None:
      session.insert(buffer.id, Prompt, None)
      discard onInput(key, buffer) or onInput(key.ord, buffer)

  if buffer.mode == 0 or buffer.prompt == StopPlaying:
    let
      col = buffer.x + 1 + buffer.cursorX - buffer.scrollX
      row = buffer.y + 1 + buffer.cursorY - buffer.scrollY
    setCursor(tb, col, row)
    var
      xBlock = tb[col, buffer.y]
      yBlock = tb[buffer.x, row]
    xBlock.fg = iw.fgYellow
    yBlock.fg = iw.fgYellow
    tb[col, buffer.y] = xBlock
    tb[buffer.x, row] = yBlock

  if buffer.mode == 0:
    case buffer.prompt:
    of None:
      discard
    of DeleteLine:
      iw.write(tb, buffer.x + 1, buffer.y, "Press Tab to delete the current line")
    of StopPlaying:
      iw.write(tb, buffer.x + 1, buffer.y, "Press Tab to stop playing")

proc renderRadioButtons(tb: var iw.TerminalBuffer, x: int, y: int, choices: openArray[tuple[id: int, label: string, callback: proc ()]], selected: int, key: iw.Key, horiz: bool, shortcut: tuple[key: iw.Key, hint: string]): int =
  const space = 2
  var
    xx = x
    yy = y
  for i in 0 ..< choices.len:
    let choice = choices[i]
    if choice.id == selected:
      iw.write(tb, xx, yy, "→")
    iw.write(tb, xx + space, yy, choice.label)
    let
      oldX = xx
      newX = xx + space + choice.label.runeLen + 1
      oldY = yy
      newY = if horiz: yy else: yy + 1
    if key == iw.Key.Mouse:
      let info = iw.getMouse()
      if info.button == iw.MouseButton.mbLeft and info.action == iw.MouseButtonAction.mbaPressed:
        if info.x >= oldX and
            info.x <= newX and
            info.y == oldY:
          session.insert(Global, HintText, shortcut.hint)
          session.insert(Global, HintTime, times.epochTime() + hintSecs)
          choice.callback()
    elif choice.id == selected and shortcut.key != iw.Key.None and shortcut.key == key:
      let nextChoice =
        if i+1 == choices.len:
          choices[0]
        else:
          choices[i+1]
      nextChoice.callback()
    if horiz:
      xx = newX
    else:
      yy = newY
  if not horiz:
    let labelWidths = sequtils.map(choices, proc (x: tuple): int = x.label.runeLen)
    xx += labelWidths[sequtils.maxIndex(labelWidths)] + space * 2
  return xx

proc renderButton(tb: var iw.TerminalBuffer, text: string, x: int, y: int, key: iw.Key, cb: proc (), shortcut: tuple[key: iw.Key, hint: string] = (iw.Key.None, "")): int =
  writeAnsi(tb, x, y, text)
  result = x + text.stripCodes.runeLen + 2
  if key == iw.Key.Mouse:
    let info = iw.getMouse()
    if info.button == iw.MouseButton.mbLeft and info.action == iw.MouseButtonAction.mbaPressed:
      if info.x >= x and
          info.x <= result and
          info.y == y:
        if shortcut.hint.len > 0:
          session.insert(Global, HintText, shortcut.hint)
          session.insert(Global, HintTime, times.epochTime() + hintSecs)
        cb()
  elif shortcut.key != iw.Key.None and shortcut.key == key:
    cb()

proc renderColors(tb: var iw.TerminalBuffer, buffer: tuple, key: iw.Key, colorX: int): int =
  const
    colorFgCodes = ["", "\e[30m", "\e[31m", "\e[32m", "\e[33m", "\e[34m", "\e[35m", "\e[36m", "\e[37m"]
    colorBgCodes = ["", "\e[40m", "\e[41m", "\e[42m", "\e[43m", "\e[44m", "\e[45m", "\e[46m", "\e[47m"]
    colorFgShortcuts = ['x', 'k', 'r', 'g', 'y', 'b', 'm', 'c', 'w']
    colorFgShortcutsSet = {'x', 'k', 'r', 'g', 'y', 'b', 'm', 'c', 'w'}
    colorBgShortcuts = ['X', 'K', 'R', 'G', 'Y', 'B', 'M', 'C', 'W']
    colorBgShortcutsSet = {'X', 'K', 'R', 'G', 'Y', 'B', 'M', 'C', 'W'}
    colorNames = ["default", "black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"]
  result = colorX + colorFgCodes.len * 3 + 1
  var colorChars = ""
  for code in colorFgCodes:
    if code == "":
      colorChars &= "╳╳"
    else:
      colorChars &= code & "██\e[0m"
    colorChars &= " "
  let fgIndex = find(colorFgCodes, buffer.selectedFgColor)
  let bgIndex = find(colorBgCodes, buffer.selectedBgColor)
  writeAnsi(tb, colorX, 0, colorChars)
  iw.write(tb, colorX + fgIndex * 3, 1, "↑")
  writeAnsi(tb, colorX + bgIndex * 3 + 1, 1, "↑")
  if key == iw.Key.Mouse:
    let info = iw.getMouse()
    if info.y == 0:
      if info.action == iw.MouseButtonAction.mbaPressed:
        if info.button == iw.MouseButton.mbLeft:
          let index = int((info.x - colorX) / 3)
          if index >= 0 and index < colorFgCodes.len:
            session.insert(buffer.id, SelectedFgColor, colorFgCodes[index])
            if buffer.mode == 1:
              session.insert(Global, HintText, "Hint: press " & colorFgShortcuts[index] & " for " & colorNames[index] & " foreground")
              session.insert(Global, HintTime, times.epochTime() + hintSecs)
        elif info.button == iw.MouseButton.mbRight:
          let index = int((info.x - colorX) / 3)
          if index >= 0 and index < colorBgCodes.len:
            session.insert(buffer.id, SelectedBgColor, colorBgCodes[index])
            if buffer.mode == 1:
              session.insert(Global, HintText, "Hint: press " & colorBgShortcuts[index] & " for " & colorNames[index] & " background")
              session.insert(Global, HintTime, times.epochTime() + hintSecs)
  elif buffer.mode == 1:
    try:
      let ch = char(key.ord)
      if ch in colorFgShortcutsSet:
        let index = find(colorFgShortcuts, ch)
        session.insert(buffer.id, SelectedFgColor, colorFgCodes[index])
      elif ch in colorBgShortcutsSet:
        let index = find(colorBgShortcuts, ch)
        session.insert(buffer.id, SelectedBgColor, colorBgCodes[index])
    except:
      discard

proc renderBrushes(tb: var iw.TerminalBuffer, buffer: tuple, key: iw.Key, brushX: int): int =
  const
    brushChars = ["█", "▓", "▒", "░", "▄", "▀", "▌", "▐"]
    brushShortcuts = ['1', '2', '3', '4', '5', '6', '7', '8']
    brushShortcutsSet = {'1', '2', '3', '4', '5', '6', '7', '8'}
  var brushCharsColored = ""
  for ch in brushChars:
    brushCharsColored &= buffer.selectedFgColor & buffer.selectedBgColor
    brushCharsColored &= ch
    brushCharsColored &= "\e[0m "
  result = brushX + brushChars.len * 2
  let brushIndex = find(brushChars, buffer.selectedChar)
  writeAnsi(tb, brushX, 0, brushCharsColored)
  iw.write(tb, brushX + brushIndex * 2, 1, "↑")
  if key == iw.Key.Mouse:
    let info = iw.getMouse()
    if info.button == iw.MouseButton.mbLeft and info.action == iw.MouseButtonAction.mbaPressed:
      if info.y == 0:
        let index = int((info.x - brushX) / 2)
        if index >= 0 and index < brushChars.len:
          session.insert(buffer.id, SelectedChar, brushChars[index])
          if buffer.mode == 1:
            session.insert(Global, HintText, "Hint: press " & brushShortcuts[index] & " for that brush")
            session.insert(Global, HintTime, times.epochTime() + hintSecs)
  elif buffer.mode == 1:
    try:
      let ch = char(key.ord)
      if ch in brushShortcutsSet:
        let index = find(brushShortcuts, ch)
        session.insert(buffer.id, SelectedChar, brushChars[index])
    except:
      discard

proc init*() =
  iw.illwillInit(fullscreen=true, mouse=true)
  setControlCHook(exitClean)
  iw.hideCursor()

  for r in rules.fields:
    session.add(r)

  const
    editorText = "\n\e[31mHello\e[0m, world!\nI always thought that one man, the lone balladeer with the guitar, could blow a whole army off the stage if he knew what he was doing; I've seen it happen.\n\n/piano c c# d\n/banjo c\n/violin d"
    tutorialText = staticRead("ansiwavepkg/assets/tutorial.ansiwave")
    publishText = staticRead("ansiwavepkg/assets/publish.ansiwave")
  insertBuffer(Editor, 0, 2, true, editorText)
  insertBuffer(Errors, 0, 1, false, "")
  insertBuffer(Tutorial, 0, 1, false, tutorialText)
  insertBuffer(Publish, 0, 1, false, publishText)
  session.insert(Global, SelectedBuffer, Editor)
  session.insert(Global, HintText, "")
  session.insert(Global, HintTime, 0.0)
  session.fireRules

  onWindowResize(iw.terminalWidth(), iw.terminalHeight())

proc tick*(): iw.TerminalBuffer =
  let key = iw.getKey()

  let
    (windowWidth, windowHeight) = session.query(rules.getTerminalWindow)
    globals = session.query(rules.getGlobals)
    selectedBuffer = session.query(rules.getBuffer, id = globals.selectedBuffer)
    width = iw.terminalWidth()
    height = iw.terminalHeight()
  var tb = iw.newTerminalBuffer(width, height)
  if width != windowWidth or height != windowHeight:
    onWindowResize(width, height)

  # render top bar
  let titleX = renderButton(tb, "\e[3m≈ANSIWAVE≈\e[0m", 1, 0, key, proc () = discard)
  if globals.selectedBuffer == Editor.ord:
    let playX =
      if selectedBuffer.prompt != StopPlaying and selectedBuffer.commands[].len > 0:
        renderButton(tb, "♫ Play", 1, 1, key, proc () = compileAndPlayAll(session, selectedBuffer), (key: iw.Key.CtrlP, hint: "Hint: play all lines with Ctrl P"))
      else:
        0
    var x = max(titleX, playX)

    let undoX = renderButton(tb, "◄ Undo", x, 0, key, proc () = echo("undo"), (key: iw.Key.CtrlZ, hint: "Hint: undo with Ctrl Z"))
    let redoX = renderButton(tb, "► Redo", x, 1, key, proc () = echo("redo"), (key: iw.Key.CtrlR, hint: "Hint: redo with Ctrl R"))
    x = max(undoX, redoX)

    let
      choices = [
        (id: 0, label: "Write Mode", callback: proc () = session.insert(selectedBuffer.id, SelectedMode, 0)),
        (id: 1, label: "Draw Mode", callback: proc () = session.insert(selectedBuffer.id, SelectedMode, 1)),
      ]
      shortcut = (key: iw.Key.CtrlE, hint: "Hint: switch modes with Ctrl E")
    x = renderRadioButtons(tb, x, 0, choices, selectedBuffer.mode, key, false, shortcut)

    x = renderColors(tb, selectedBuffer, key, x + 1)

    if selectedBuffer.mode == 1:
      x = renderBrushes(tb, selectedBuffer, key, x + 2)

  renderBuffer(tb, selectedBuffer, key)

  # render bottom bar
  var x = 0
  if selectedBuffer.prompt != StopPlaying:
    let
      errorCount = session.query(rules.getBuffer, id = Editor).errors[].len
      choices = [
        (id: Editor.ord, label: "Editor", callback: proc () {.closure.} = session.insert(Global, SelectedBuffer, Editor)),
        (id: Errors.ord, label: strutils.format("Errors ($1)", errorCount), callback: proc () {.closure.} = session.insert(Global, SelectedBuffer, Errors)),
        (id: Tutorial.ord, label: "Tutorial", callback: proc () {.closure.} = session.insert(Global, SelectedBuffer, Tutorial)),
        (id: Publish.ord, label: "Publish", callback: proc () {.closure.} = session.insert(Global, SelectedBuffer, Publish)),
      ]
      shortcut = (key: iw.Key.CtrlN, hint: "Hint: switch tabs with Ctrl N")
    x = renderRadioButtons(tb, 0, windowHeight - 1, choices, globals.selectedBuffer, key, true, shortcut)

  # render hints
  if globals.hintTime > 0 and times.epochTime() >= globals.hintTime:
    session.insert(Global, HintText, "")
    session.insert(Global, HintTime, 0.0)
  else:
    let
      showHint = globals.hintText.len > 0
      text =
        if showHint:
          globals.hintText
        else:
          "‼ Exit"
      textX = max(x + 2, selectedBuffer.width + 1 - text.runeLen)
    if showHint:
      writeAnsi(tb, textX, windowHeight - 1, "\e[3m" & text & "\e[0m")
    elif selectedBuffer.prompt != StopPlaying:
      let cb =
        proc () =
          session.insert(Global, HintText, "Press Ctrl C to exit")
          session.insert(Global, HintTime, times.epochTime() + hintSecs)
      discard renderButton(tb, text, textX, windowHeight - 1, key, cb)

  return tb

when isMainModule:
  init()
  var tickCount = 0
  while true:
    var tb = tick()
    # don't render every tick because it's wasteful
    if tickCount mod 5 == 0:
      iw.display(tb)
    session.fireRules
    os.sleep(sleepMsecs)
    tickCount.inc
