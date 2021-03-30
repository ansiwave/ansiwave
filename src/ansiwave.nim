import ansiwavepkg/illwill as iw
import tables
import pararules
import unicode
from os import nil
from strutils import nil

#import ansiwavepkg/ansi
#const content = staticRead("../luke_and_yoda.ans")
#print(ansiToUtf8(content))

proc stripCodes(line: seq[Rune]): string =
  var codes: seq[string]
  for ch in line:
    if parseCode(codes, ch):
      continue
    result &= $ch

proc stripCodes(line: string): string =
  stripCodes(line.toRunes)

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

proc lineLen(line: string): int =
  if strutils.endsWith(line, "\n"):
    line.runeLen - 1
  else:
    line.runeLen

proc lineLen(line: seq[Rune]): int =
  if line.len > 0 and line[line.len - 1] == "\n".runeAt(0):
    line.len - 1
  else:
    line.len

proc splitLinesRetainingNewline(text: string): seq[string] =
  var rest = text
  while true:
    let i = strutils.find(rest, "\n")
    if i == -1:
      result.add(rest)
      break
    else:
      result.add(rest[0 .. i])
      rest = rest[i + 1 ..< rest.len]

type
  Id* = enum
    Global, TerminalWindow,
  Attr* = enum
    CursorX, CursorY,
    ScrollX, ScrollY,
    X, Y, Width, Height,
    CurrentBufferId, Lines,
    CurrentModalId,
    Wrap, Editable, Mode,
    SelectedChar,
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
  CurrentModalId: int
  Lines: RefStrings
  Wrap: bool
  Editable: bool
  Mode: int
  SelectedChar: string

let rules =
  ruleset:
    rule getGlobals(Fact):
      what:
        (Global, CurrentBufferId, currentBuffer)
        (Global, CurrentModalId, currentModal)
    rule getTerminalWindow(Fact):
      what:
        (TerminalWindow, Width, windowWidth)
        (TerminalWindow, Height, windowHeight)
    rule updateTerminalScrollX(Fact):
      what:
        (id, Width, bufferWidth)
        (id, CursorX, cursorX)
        (id, ScrollX, scrollX, then = false)
        (id, Wrap, wrap)
      cond:
        wrap == false
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
        (id, Wrap, wrap)
      then:
        if cursorY < 0:
          session.insert(id, CursorY, 0)
        elif cursorY >= lines[].len:
          session.insert(id, CursorY, lines[].len - 1)
        else:
          if wrap:
            if cursorX > lines[cursorY].stripCodes.lineLen:
              if cursorY == lines[].len - 1:
                session.insert(id, CursorX, lines[cursorY].stripCodes.lineLen)
              else:
                session.insert(id, CursorY, cursorY + 1)
                session.insert(id, CursorX, 0)
            elif cursorX < 0:
              if cursorY == 0:
                session.insert(id, CursorX, 0)
              else:
                session.insert(id, CursorY, cursorY - 1)
                session.insert(id, CursorX, lines[cursorY - 1].stripCodes.lineLen)
          else:
            if cursorX > lines[cursorY].stripCodes.lineLen:
              session.insert(id, CursorX, lines[cursorY].stripCodes.lineLen)
            elif cursorX < 0:
              session.insert(id, CursorX, 0)
    rule wrapText(Fact):
      what:
        (id, Wrap, wrap)
        (id, Lines, lines, then = false)
        (id, Width, bufferWidth)
      cond:
        wrap
        bufferWidth > 0
      then:
        let
          fullLines = splitLinesRetainingNewline(strutils.join(lines[]))
          lineColumns = bufferWidth - 1
        var wrapLines: seq[seq[string]]
        for line in fullLines:
          var parts: seq[seq[Rune]]
          var rest = line.toRunes
          while true:
            if rest.lineLen > lineColumns:
              parts.add(rest[0 ..< lineColumns])
              rest = rest[lineColumns ..< rest.len]
            else:
              parts.add(rest)
              break
          var strs: seq[string]
          for part in parts:
            strs.add($ part)
          wrapLines.add(strs)
        var newLines: ref seq[string]
        new newLines
        for line in wrapLines:
          newLines[].add(line)
        session.insert(id, Lines, newLines)
    rule getBuffer(Fact):
      what:
        (id, CursorX, cursorX)
        (id, CursorY, cursorY)
        (id, ScrollX, scrollX)
        (id, ScrollY, scrollY)
        (id, Lines, lines)
        (id, Wrap, wrap)
        (id, X, x)
        (id, Y, y)
        (id, Width, width)
        (id, Height, height)
        (id, Editable, editable)
        (id, Mode, mode)
        (id, SelectedChar, selectedChar)

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
  session.insert(currentBuffer.id, Height, height - 4)

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
  session.insert(Global, CurrentModalId, -1)

  session.insert(bufferId, CursorX, 0)
  session.insert(bufferId, CursorY, 0)
  session.insert(bufferId, ScrollX, 0)
  session.insert(bufferId, ScrollY, 0)
  var lines: RefStrings
  new lines
  lines[] = splitLinesRetainingNewline(text)
  session.insert(bufferId, Lines, lines)
  session.insert(bufferId, X, 0)
  session.insert(bufferId, Y, 2)
  session.insert(bufferId, Width, 80)
  session.insert(bufferId, Height, 0)
  session.insert(bufferId, Wrap, false)
  session.insert(bufferId, Editable, true)
  session.insert(bufferId, Mode, 0)
  session.insert(bufferId, SelectedChar, "█")

  onWindowResize(iw.terminalWidth(), iw.terminalHeight())

proc setCharBackground(tb: var iw.TerminalBuffer, col: int, row: int, color: iw.BackgroundColor, cursor: bool) =
  if col < 0 or row < 0:
    return
  var ch = tb[col, row]
  ch.bg = color
  tb[col, row] = ch
  if cursor:
    iw.setCursorPos(tb, col, row)

proc onInput(ch: string, buffer: tuple) =
  case ch:
  of "<BS>":
    if not buffer.editable:
      return
    if buffer.cursorX > 0:
      let
        line = buffer.lines[buffer.cursorY].toRunes
        realX = getRealX(line, buffer.cursorX - 1)
        newLine = $line[0 ..< realX] & $line[realX + 1 ..< line.len]
      var newLines = buffer.lines
      newLines[buffer.cursorY] = newLine
      session.insert(buffer.id, Lines, newLines)
      session.insert(buffer.id, CursorX, buffer.cursorX - 1)
      session.insert(buffer.id, Width, buffer.width) # force refresh
  of "<Del>":
    if not buffer.editable:
      return
    if buffer.cursorX < buffer.lines[buffer.cursorY].stripCodes.lineLen:
      let
        line = buffer.lines[buffer.cursorY].toRunes
        realX = getRealX(line, buffer.cursorX)
        newLine = $line[0 ..< realX] & $line[realX + 1 ..< line.len]
      var newLines = buffer.lines
      newLines[buffer.cursorY] = newLine
      session.insert(buffer.id, Lines, newLines)
      session.insert(buffer.id, Width, buffer.width) # force refresh
  of "<Enter>":
    if not buffer.editable:
      return
    let
      line = buffer.lines[buffer.cursorY].toRunes
      realX = getRealX(line, buffer.cursorX)
      before = line[0 ..< realX]
      after = line[realX ..< line.len]
      keepCursorOnLine = buffer.wrap and
                         buffer.cursorX == 0 and
                         buffer.cursorY > 0 and
                         not strutils.endsWith(buffer.lines[buffer.cursorY - 1], "\n")
    var newLines: ref seq[string]
    new newLines
    newLines[] = buffer.lines[][0 ..< buffer.cursorY]
    if keepCursorOnLine:
      newLines[newLines[].len - 1] &= "\n"
    else:
      newLines[].add($before & "\n")
    newLines[].add($after)
    newLines[].add(buffer.lines[][buffer.cursorY + 1 ..< buffer.lines[].len])
    session.insert(buffer.id, Lines, newLines)
    session.insert(buffer.id, Width, buffer.width) # force refresh
    session.insert(buffer.id, CursorX, 0)
    if not keepCursorOnLine:
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
    session.insert(buffer.id, CursorX, buffer.lines[buffer.cursorY].lineLen)

proc onInput(ch: char, buffer: tuple) =
  if not buffer.editable:
    return
  let
    line = buffer.lines[buffer.cursorY].toRunes
    realX = getRealX(line, buffer.cursorX)
    newLine = $line[0 ..< realX] & $ch & $line[realX ..< line.len]
  var newLines = buffer.lines
  newLines[buffer.cursorY] = newLine
  session.insert(buffer.id, Lines, newLines)
  session.insert(buffer.id, CursorX, buffer.cursorX + 1)
  session.insert(buffer.id, Width, buffer.width) # force refresh

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
    line = line[0 ..< lines[i].lineLen]
    if scrollX < line.stripCodes.lineLen:
      if scrollX > 0:
        deleteBefore(line, scrollX)
    else:
      line = @[]
    deleteAfter(line, buffer.width - 1)
    iw.write(tb, buffer.x + 1, buffer.y + 1 + screenLine, $line)
    screenLine += 1

  if key == Key.Mouse:
    let info = getMouse()
    if info.button == mbLeft and info.action == mbaPressed:
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
          while x > line.stripCodes.lineLen - 1:
            line.add(" ".runeAt(0))
          let realX = getRealX(line, x)
          line[realX] = buffer.selectedChar.runeAt(0)
          lines[y] = $ line
  elif focused and buffer.mode == 0:
    let code = key.ord
    if iwToSpecials.hasKey(code):
      onInput(iwToSpecials[code], buffer)
    elif code >= 32:
      onInput(char(code), buffer)

  if focused and buffer.mode == 0:
    let
      col = buffer.x + 1 + buffer.cursorX - buffer.scrollX
      row = buffer.y + 1 + buffer.cursorY - buffer.scrollY
    setCharBackground(tb, col, row, iw.bgYellow, true)

proc renderRadioButtons(tb: var TerminalBuffer, x: int, y: int, labels: openArray[string], buffer: tuple, key: Key) =
  iw.write(tb, x, y + buffer.mode, "→")
  const space = 2
  var i = 0
  for label in labels:
    let style = tb.getStyle()
    iw.write(tb, x + space, y + i, label)
    if key == Key.Mouse:
      let info = getMouse()
      if info.button == mbLeft and info.action == mbaPressed:
        if info.x >= x + space and
            info.x <= x + space + label.len and
            info.y >= y + i and
            info.y <= y + i + 1:
          session.insert(buffer.id, Mode, i)
    i = i + 1

proc renderModal(tb: var TerminalBuffer, buffer: tuple, key: Key) =
  let spaces = strutils.repeat(' ', buffer.width)
  for i in buffer.y ..< buffer.y + buffer.height:
    iw.write(tb, buffer.x + 1, i, spaces)
  renderBuffer(tb, buffer, true, key)
  if key == iw.Key.Escape:
    session.insert(Global, CurrentModalId, -1)

proc renderBrushes(tb: var TerminalBuffer, buffer: tuple, key: Key) =
  const
    brushChars = ["█", "▓", "▒", "░"]
    brushCharsJoined = strutils.join(brushChars, " ")
    brushX = 16
  let brushIndex = find(brushChars, buffer.selectedChar)
  iw.write(tb, brushX, 0, brushCharsJoined)
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

  renderRadioButtons(tb, 0, 0, ["Write Mode", "Draw Mode"], currentBuffer, key)

  if currentBuffer.mode == 1:
    renderBrushes(tb, currentBuffer, key)

  renderBuffer(tb, currentBuffer, globals.currentModal == -1, key)

  if globals.currentModal != -1:
    renderModal(tb, session.query(rules.getBuffer, id = globals.currentModal), key)

  session.fireRules()

  iw.display(tb)

when isMainModule:
  init()
  while true:
    tick()
    os.sleep(10)
