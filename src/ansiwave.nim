import illwill as iw
import tables
import pararules
from os import nil
from strutils import nil

#import ansiwavepkg/ansi
#const content = staticRead("../luke_and_yoda.ans")
#print(ansiToUtf8(content))

proc lineLen(line: string): int =
  if strutils.endsWith(line, "\n"):
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
    Wrap, Editable, Mode,
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
  Wrap: bool
  Editable: bool
  Mode: int

let rules =
  ruleset:
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
            if cursorX > lines[cursorY].lineLen:
              session.insert(id, CursorY, cursorY + 1)
              session.insert(id, CursorX, 0)
            elif cursorX < 0:
              session.insert(id, CursorY, cursorY - 1)
              session.insert(id, CursorX, lines[cursorY - 1].lineLen)
          else:
            if cursorX > lines[cursorY].lineLen:
              session.insert(id, CursorX, lines[cursorY].lineLen)
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
          var parts: seq[string]
          var rest = line
          while true:
            if rest.lineLen > lineColumns:
              parts.add(rest[0 ..< lineColumns])
              rest = rest[lineColumns ..< rest.len]
            else:
              parts.add(rest)
              break
          wrapLines.add(parts)
        var newLines: ref seq[string]
        new newLines
        for line in wrapLines:
          newLines[].add(line)
        session.insert(id, Lines, newLines)
    rule getCurrentBuffer(Fact):
      what:
        (Global, CurrentBufferId, id)
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
  let currentBuffer = session.query(rules.getCurrentBuffer)
  session.insert(currentBuffer.id, Width, width - 2)
  session.insert(currentBuffer.id, Height, height - 2)

proc exitProc() {.noconv.} =
  iw.illwillDeinit()
  iw.showCursor()
  quit(0)

const text = "\nHello, world!\nI always thought that one man, the lone balladeer with the guitar, could blow a whole army off the stage if he knew what he was doing; I've seen it happen."

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
  lines[] = splitLinesRetainingNewline(text)
  session.insert(bufferId, Lines, lines)
  session.insert(bufferId, X, 0)
  session.insert(bufferId, Y, 2)
  session.insert(bufferId, Width, 0)
  session.insert(bufferId, Height, 0)
  session.insert(bufferId, Wrap, false)
  session.insert(bufferId, Editable, true)
  session.insert(bufferId, Mode, 0)

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
        line = buffer.lines[buffer.cursorY]
        newLine = line[0 ..< buffer.cursorX - 1] & line[buffer.cursorX ..< line.len]
      var newLines = buffer.lines
      newLines[buffer.cursorY] = newLine
      session.insert(buffer.id, Lines, newLines)
      session.insert(buffer.id, CursorX, buffer.cursorX - 1)
      session.insert(buffer.id, Width, buffer.width) # force refresh
  of "<Del>":
    if not buffer.editable:
      return
    if buffer.cursorX < buffer.lines[buffer.cursorY].lineLen:
      let
        line = buffer.lines[buffer.cursorY]
        newLine = line[0 ..< buffer.cursorX] & line[buffer.cursorX + 1 ..< line.len]
      var newLines = buffer.lines
      newLines[buffer.cursorY] = newLine
      session.insert(buffer.id, Lines, newLines)
      session.insert(buffer.id, Width, buffer.width) # force refresh
  of "<Enter>":
    if not buffer.editable:
      return
    let
      line = buffer.lines[buffer.cursorY]
      before = line[0 ..< buffer.cursorX]
      after = line[buffer.cursorX ..< line.len]
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
      newLines[].add(before & "\n")
    newLines[].add(after)
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
    line = buffer.lines[buffer.cursorY]
    newLine = line[0 ..< buffer.cursorX] & $ch & line[buffer.cursorX ..< line.len]
  var newLines = buffer.lines
  newLines[buffer.cursorY] = newLine
  session.insert(buffer.id, Lines, newLines)
  session.insert(buffer.id, CursorX, buffer.cursorX + 1)
  session.insert(buffer.id, Width, buffer.width) # force refresh

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

proc renderBuffer(tb: var TerminalBuffer, buffer: tuple, focused: bool, key: Key) =
  tb.drawRect(buffer.x, buffer.y, buffer.width + 1, buffer.height + 1, doubleStyle = focused)
  let
    lines = buffer.lines[]
    scrollX = buffer.scrollX
    scrollY = buffer.scrollY
  var screenLine = 0
  for i in scrollY ..< lines.len:
    if screenLine > buffer.height - 1:
      break
    var line = lines[i][0 ..< lines[i].lineLen]
    if scrollX < line.lineLen:
      if scrollX > 0:
        line = line[scrollX ..< line.lineLen]
    else:
      line = ""
    if line.lineLen > buffer.width:
      line = line[0 ..< buffer.width]
    iw.write(tb, buffer.x + 1, buffer.y + 1 + screenLine, line)
    screenLine += 1

  if key == Key.Mouse:
    let info = getMouse()
    if info.button == mbLeft and info.action == mbaPressed:
      if buffer.mode == 0 and
          info.x >= buffer.x and
          info.x <= buffer.x + buffer.width and
          info.y >= buffer.y and
          info.y <= buffer.y + buffer.height:
        session.insert(buffer.id, CursorX, info.x - (buffer.x + 1 - buffer.scrollX))
        session.insert(buffer.id, CursorY, info.y - (buffer.y + 1 - buffer.scrollY))
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

proc tick*() =
  let key = iw.getKey()

  let
    (windowWidth, windowHeight) = session.query(rules.getTerminalWindow)
    currentBuffer = session.query(rules.getCurrentBuffer)
    width = iw.terminalWidth()
    height = iw.terminalHeight()
  var tb = iw.newTerminalBuffer(width, height)
  if width != windowWidth or height != windowHeight:
    onWindowResize(width, height)

  renderRadioButtons(tb, 0, 0, ["Keyboard Mode", "Draw Mode"], currentBuffer, key)
  iw.write(tb, 20, 0, "█▓▒░")
  iw.write(tb, 20, 1, "↑")

  renderBuffer(tb, currentBuffer, true, key)

  session.fireRules()

  iw.display(tb)

when isMainModule:
  init()
  while true:
    tick()
    os.sleep(10)
