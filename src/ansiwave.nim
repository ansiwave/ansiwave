import illwill as iw
import tables
import pararules
import unicode
from os import nil
from strutils import nil
from sequtils import nil
import ansiwavepkg/ansi

#const content = staticRead("../luke_and_yoda.ans")
#print(ansiToUtf8(content))
#quit()

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

proc applyCode(tb: var TerminalBuffer, code: string) =
  let trimmed = code[1 ..< code.len - 1]
  let params = ansi.parseParams(trimmed)
  for param in params:
    if param == 0:
      tb.setBackgroundColor(bgNone)
      tb.setForegroundColor(fgNone)
      tb.setStyle({})
    elif param >= 1 and param <= 9:
      var style = tb.getStyle()
      style.incl(Style(param))
      tb.setStyle(style)
    elif param >= 30 and param <= 39:
      tb.setForegroundColor(ForegroundColor(param))
    elif param >= 40 and param <= 49:
      tb.setBackgroundColor(BackgroundColor(param))

proc writeAnsi(tb: var TerminalBuffer, x, y: Natural, s: string) =
  var currX = x
  var codes: seq[string]
  for ch in runes(s):
    if parseCode(codes, ch):
      continue
    for code in codes:
      applyCode(tb, code)
    var c = TerminalChar(ch: ch, fg: tb.getForegroundColor, bg: tb.getBackgroundColor,
                         style: tb.getStyle)
    tb[currX, y] = c
    inc(currX)
    codes = @[]
  for code in codes:
    applyCode(tb, code)
  tb.setCursorXPos(currX)
  tb.setCursorYPos(y)

proc stripCodes(line: seq[Rune]): string =
  var codes: seq[string]
  for ch in line:
    if parseCode(codes, ch):
      continue
    result &= $ch

proc stripCodes(line: string): string =
  stripCodes(line.toRunes)

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
  Attr* = enum
    CursorX, CursorY,
    ScrollX, ScrollY,
    X, Y, Width, Height,
    CurrentBufferId, Lines,
    Editable, SelectedMode, SelectedTab,
    SelectedChar, SelectedFgColor, SelectedBgColor,
    Prompt,
  PromptKind = enum
    None, DeleteLine,
  RefStrings = ref seq[string]

schema Fact(Id, Attr):
  CursorX: int
  CursorY: int
  ScrollX: int
  ScrollY: int
  X: int
  Y: int
  Width: int
  Height: int
  CurrentBufferId: int
  Lines: RefStrings
  Editable: bool
  SelectedMode: int
  SelectedTab: int
  SelectedChar: string
  SelectedFgColor: string
  SelectedBgColor: string
  Prompt: PromptKind

let rules =
  ruleset:
    rule getGlobals(Fact):
      what:
        (Global, CurrentBufferId, currentBuffer)
    rule getTerminalWindow(Fact):
      what:
        (TerminalWindow, Width, windowWidth)
        (TerminalWindow, Height, windowHeight)
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
        if cursorY < 0:
          session.insert(id, CursorY, 0)
        elif cursorY >= lines[].len:
          session.insert(id, CursorY, lines[].len - 1)
        else:
          if cursorX > lines[cursorY].stripCodes.runeLen:
            session.insert(id, CursorX, lines[cursorY].stripCodes.runeLen)
          elif cursorX < 0:
            session.insert(id, CursorX, 0)
    rule addClearToBeginningOfEveryLine(Fact):
      what:
        (id, Lines, lines)
      then:
        var shouldInsert = false
        for i in 0 ..< lines[].len:
          if lines[i].len == 0 or not strutils.startsWith(lines[i], "\e[0"):
            lines[i] = dedupeCodes("\e[0m" & lines[i])
            shouldInsert = true
        if shouldInsert:
          session.insert(id, Lines, lines)
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
        (id, SelectedTab, tab)
        (id, SelectedChar, selectedChar)
        (id, SelectedFgColor, selectedFgColor)
        (id, SelectedBgColor, selectedBgColor)
        (id, Prompt, prompt)

var session* = initSession(Fact, autoFire = false)

const iwToSpecials =
  {iw.Key.Backspace.ord: "<BS>",
   iw.Key.Delete.ord: "<Del>",
   iw.Key.Tab.ord: "<Tab>",
   iw.Key.Enter.ord: "<Enter>",
   iw.Key.Escape.ord: "<Esc>",
   iw.Key.Up.ord: "<Up>",
   iw.Key.Down.ord: "<Down>",
   iw.Key.Left.ord: "<Left>",
   iw.Key.Right.ord: "<Right>",
   iw.Key.Home.ord: "<Home>",
   iw.Key.End.ord: "<End>",
   iw.Key.PageUp.ord: "<PageUp>",
   iw.Key.PageDown.ord: "<PageDown>",
   iw.Key.CtrlD.ord: "<C-D>",
   iw.Key.CtrlR.ord: "<C-R>",
   iw.Key.CtrlU.ord: "<C-U>",
   iw.Key.CtrlV.ord: "<C-V>",}.toTable

proc onWindowResize(width: int, height: int) =
  session.insert(TerminalWindow, Width, width)
  session.insert(TerminalWindow, Height, height)
  let globals = session.query(rules.getGlobals)
  let currentBuffer = session.query(rules.getBuffer, id = globals.currentBuffer)
  session.insert(currentBuffer.id, Height, height - 5)

proc exitProc() {.noconv.} =
  iw.illwillDeinit()
  iw.showCursor()
  quit(0)

const text = "\n\e[31mHello\e[0m, world!\nI always thought that one man, the lone balladeer with the guitar, could blow a whole army off the stage if he knew what he was doing; I've seen it happen."

proc init*() =
  iw.illwillInit(fullscreen=true, mouse=true)
  setControlCHook(exitProc)
  iw.hideCursor()

  for r in rules.fields:
    session.add(r)

  let bufferId = Id.high.ord + 1

  session.insert(Global, CurrentBufferId, bufferId)

  session.insert(bufferId, CursorX, 0)
  session.insert(bufferId, CursorY, 0)
  session.insert(bufferId, ScrollX, 0)
  session.insert(bufferId, ScrollY, 0)
  var lines: RefStrings
  new lines
  lines[] = strutils.splitLines(text)
  session.insert(bufferId, Lines, lines)
  session.insert(bufferId, X, 0)
  session.insert(bufferId, Y, 2)
  session.insert(bufferId, Width, 80)
  session.insert(bufferId, Height, 0)
  session.insert(bufferId, Editable, true)
  session.insert(bufferId, SelectedMode, 0)
  session.insert(bufferId, SelectedTab, 0)
  session.insert(bufferId, SelectedChar, "█")
  session.insert(bufferId, SelectedFgColor, "")
  session.insert(bufferId, SelectedBgColor, "")
  session.insert(bufferId, Prompt, None)

  onWindowResize(iw.terminalWidth(), iw.terminalHeight())

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

proc onInput(ch: string, buffer: tuple) =
  case ch:
  of "<BS>":
    if not buffer.editable:
      return
    if buffer.cursorX == 0:
      session.insert(buffer.id, Prompt, DeleteLine)
    elif buffer.cursorX > 0:
      let
        line = buffer.lines[buffer.cursorY].toRunes
        realX = getRealX(line, buffer.cursorX - 1)
        newLine = dedupeCodes($line[0 ..< realX] & $line[realX + 1 ..< line.len])
      var newLines = buffer.lines
      newLines[buffer.cursorY] = newLine
      session.insert(buffer.id, Lines, newLines)
      session.insert(buffer.id, CursorX, buffer.cursorX - 1)
  of "<Del>":
    if not buffer.editable:
      return
    if buffer.cursorX == buffer.lines[buffer.cursorY].stripCodes.runeLen:
      session.insert(buffer.id, Prompt, DeleteLine)
    elif buffer.cursorX < buffer.lines[buffer.cursorY].stripCodes.runeLen:
      let
        line = buffer.lines[buffer.cursorY].toRunes
        realX = getRealX(line, buffer.cursorX)
        newLine = dedupeCodes($line[0 ..< realX] & $line[realX + 1 ..< line.len])
      var newLines = buffer.lines
      newLines[buffer.cursorY] = newLine
      session.insert(buffer.id, Lines, newLines)
  of "<Enter>":
    if not buffer.editable:
      return
    let
      line = buffer.lines[buffer.cursorY].toRunes
      realX = getRealX(line, buffer.cursorX)
      prefix = "\e[" & strutils.join(@[0] & getParamsBeforeRealX(line, realX), ";") & "m"
      before = line[0 ..< realX]
      after = line[realX ..< line.len]
    var newLines: ref seq[string]
    new newLines
    newLines[] = buffer.lines[][0 ..< buffer.cursorY]
    newLines[].add($before)
    newLines[].add(prefix & $after)
    newLines[].add(buffer.lines[][buffer.cursorY + 1 ..< buffer.lines[].len])
    session.insert(buffer.id, Lines, newLines)
    session.insert(buffer.id, CursorX, 0)
    session.insert(buffer.id, CursorY, buffer.cursorY + 1)
  of "<Up>":
    session.insert(buffer.id, CursorY, buffer.cursorY - 1)
  of "<Down>":
    session.insert(buffer.id, CursorY, buffer.cursorY + 1)
  of "<Left>":
    session.insert(buffer.id, CursorX, buffer.cursorX - 1)
  of "<Right>":
    session.insert(buffer.id, CursorX, buffer.cursorX + 1)
  of "<Home>":
    session.insert(buffer.id, CursorX, 0)
  of "<End>":
    session.insert(buffer.id, CursorX, buffer.lines[buffer.cursorY].stripCodes.runeLen)
  of "<Esc>":
    case buffer.prompt:
    of None:
      discard
    of DeleteLine:
      var newLines = buffer.lines
      if newLines[].len == 1:
        newLines[0] = ""
      else:
        newLines[].delete(buffer.cursorY)
      session.insert(buffer.id, Lines, newLines)
      if buffer.cursorY > newLines[].len - 1:
        session.insert(buffer.id, CursorY, newLines[].len - 1)

proc makePrefix(buffer: tuple): string =
  if buffer.selectedFgColor == "" and buffer.selectedBgColor != "":
    result = "\e[0m" & buffer.selectedBgColor
  elif buffer.selectedFgColor != "" and buffer.selectedBgColor == "":
    result = "\e[0m" & buffer.selectedFgColor
  elif buffer.selectedFgColor == "" and buffer.selectedBgColor == "":
    result = "\e[0m"
  elif buffer.selectedFgColor != "" and buffer.selectedBgColor != "":
    result = buffer.selectedFgColor & buffer.selectedBgColor

proc onInput(ch: char, buffer: tuple) =
  if not buffer.editable:
    return
  let
    line = buffer.lines[buffer.cursorY].toRunes
    realX = getRealX(line, buffer.cursorX)
    prefix = buffer.makePrefix
    suffix = "\e[" & strutils.join(@[0] & getParamsBeforeRealX(line, realX), ";") & "m"
    chColored = prefix & $ch & suffix
    newLine = dedupeCodes($line[0 ..< realX] & chColored & $line[realX ..< line.len])
  var newLines = buffer.lines
  newLines[buffer.cursorY] = newLine
  session.insert(buffer.id, Lines, newLines)
  session.insert(buffer.id, CursorX, buffer.cursorX + 1)

proc renderBuffer(tb: var TerminalBuffer, buffer: tuple, focused: bool, key: Key) =
  tb.drawRect(buffer.x, buffer.y, buffer.x + buffer.width + 1, buffer.y + buffer.height + 1, doubleStyle = focused)
  let
    lines = buffer.lines[]
    scrollX = buffer.scrollX
    scrollY = buffer.scrollY
  var screenLine = 0
  for i in scrollY ..< lines.len:
    if screenLine > buffer.height - 1:
      break
    var line = lines[i].toRunes
    line = line[0 ..< lines[i].runeLen]
    if scrollX < line.stripCodes.runeLen:
      if scrollX > 0:
        deleteBefore(line, scrollX)
    else:
      line = @[]
    deleteAfter(line, buffer.width - 1)
    writeAnsi(tb, buffer.x + 1, buffer.y + 1 + screenLine, $line)
    screenLine += 1

  if key == Key.Mouse:
    let info = getMouse()
    if info.button == mbLeft and info.action == mbaPressed:
      session.insert(buffer.id, Prompt, None)
      if info.x > buffer.x and
          info.x <= buffer.x + buffer.width and
          info.y > buffer.y and
          info.y <= buffer.y + buffer.height:
        if buffer.mode == 0:
            session.insert(buffer.id, CursorX, info.x - (buffer.x + 1 - buffer.scrollX))
            session.insert(buffer.id, CursorY, info.y - (buffer.y + 1 - buffer.scrollY))
        elif buffer.mode == 1:
          let
            x = info.x - buffer.x - 1 + buffer.scrollX
            y = info.y - buffer.y - 1 + buffer.scrollY
          var lines = buffer.lines
          while y > lines[].len - 1:
            lines[].add("")
          var line = lines[y].toRunes
          while x > line.stripCodes.runeLen - 1:
            line.add(" ".runeAt(0))
          let realX = getRealX(line, x)
          line[realX] = buffer.selectedChar.runeAt(0)
          let prefix = buffer.makePrefix
          let suffix = "\e[" & strutils.join(@[0] & getParamsBeforeRealX(line, realX), ";") & "m"
          lines[y] = dedupeCodes($line[0 ..< realX] & prefix & buffer.selectedChar & suffix & $line[realX + 1 ..< line.len])
  elif focused and buffer.mode == 0:
    let code = key.ord
    if iwToSpecials.hasKey(code):
      session.insert(buffer.id, Prompt, None)
      onInput(iwToSpecials[code], buffer)
    elif code >= 32:
      session.insert(buffer.id, Prompt, None)
      onInput(char(code), buffer)

  if focused and buffer.mode == 0:
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

  case buffer.prompt:
  of None:
    discard
  of DeleteLine:
    iw.write(tb, buffer.x + 1, buffer.y, "Press Esc to delete the current line")

proc renderRadioButtons(tb: var TerminalBuffer, x: int, y: int, labels: openArray[string], bufferId: int, attr: Attr, selected: int, key: Key, horiz: bool): int =
  const space = 2
  var
    i = 0
    xx = x
    yy = y
  for label in labels:
    if i == selected:
      iw.write(tb, xx, yy, "→")
    iw.write(tb, xx + space, yy, label)
    let
      oldX = xx
      newX = xx + space + label.len + 1
      oldY = yy
      newY = if horiz: yy else: yy + 1
    if key == Key.Mouse:
      let info = getMouse()
      if info.button == mbLeft and info.action == mbaPressed:
        if info.x >= oldX and
            info.x <= newX and
            info.y == oldY:
          session.insert(bufferId, attr, i)
    if horiz:
      xx = newX
    else:
      yy = newY
    i = i + 1
  if not horiz:
    let labelWidths = sequtils.map(labels, proc (x: string): int = x.len)
    xx += labelWidths[sequtils.maxIndex(labelWidths)] + space * 2
  return xx

proc renderColors(tb: var TerminalBuffer, buffer: tuple, key: Key, colorX: int): int =
  const
    colorFgCodes = ["", "\e[30m", "\e[31m", "\e[32m", "\e[33m", "\e[34m", "\e[35m", "\e[36m", "\e[37m"]
    colorBgCodes = ["", "\e[40m", "\e[41m", "\e[42m", "\e[43m", "\e[44m", "\e[45m", "\e[46m", "\e[47m"]
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
  iw.write(tb, colorX + fgIndex * 3, 1, "F")
  iw.write(tb, colorX + bgIndex * 3 + 1, 1, "B")
  if key == Key.Mouse:
    let info = getMouse()
    if info.y == 0:
      if info.action == mbaPressed:
        if info.button == mbLeft:
          let index = int((info.x - colorX) / 3)
          if index >= 0 and index < colorFgCodes.len:
            session.insert(buffer.id, SelectedFgColor, colorFgCodes[index])
        elif info.button == mbRight:
          let index = int((info.x - colorX) / 3)
          if index >= 0 and index < colorBgCodes.len:
            session.insert(buffer.id, SelectedBgColor, colorBgCodes[index])

proc renderBrushes(tb: var TerminalBuffer, buffer: tuple, key: Key, brushX: int): int =
  const brushChars = ["█", "▓", "▒", "░"]
  var brushCharsColored = ""
  for ch in brushChars:
    brushCharsColored &= buffer.selectedFgColor & buffer.selectedBgColor
    brushCharsColored &= ch
    brushCharsColored &= "\e[0m "
  result = brushX + brushChars.len * 2
  let brushIndex = find(brushChars, buffer.selectedChar)
  writeAnsi(tb, brushX, 0, brushCharsColored)
  iw.write(tb, brushX + brushIndex * 2, 1, "↑")
  if key == Key.Mouse:
    let info = getMouse()
    if info.button == mbLeft and info.action == mbaPressed:
      if info.y == 0:
        let index = int((info.x - brushX) / 2)
        if index >= 0 and index < brushChars.len:
          session.insert(buffer.id, SelectedChar, brushChars[index])

proc tick*() =
  let key = iw.getKey()

  let
    (windowWidth, windowHeight) = session.query(rules.getTerminalWindow)
    globals = session.query(rules.getGlobals)
    currentBuffer = session.query(rules.getBuffer, id = globals.currentBuffer)
    width = iw.terminalWidth()
    height = iw.terminalHeight()
  var tb = iw.newTerminalBuffer(width, height)
  if width != windowWidth or height != windowHeight:
    onWindowResize(width, height)

  var x = renderRadioButtons(tb, 0, 0, ["Write Mode", "Draw Mode"], currentBuffer.id, SelectedMode, currentBuffer.mode, key, false)

  x = renderColors(tb, currentBuffer, key, x)

  if currentBuffer.mode == 1:
    x = renderBrushes(tb, currentBuffer, key, x)

  renderBuffer(tb, currentBuffer, true, key)

  x = renderRadioButtons(tb, 0, windowHeight - 1, ["Editor", strutils.format("Errors ($1)", 0), "Help"], currentBuffer.id, SelectedTab, currentBuffer.tab, key, true)

  session.fireRules()

  iw.display(tb)

when isMainModule:
  init()
  while true:
    tick()
    os.sleep(10)
