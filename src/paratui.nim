import illwill as iw
import tables
import pararules
from os import nil
from strutils import nil

#import paratuipkg/ansi
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
    Window
  Attr* = enum
    CursorX, CursorY,
    ScrollX, ScrollY,
    X, Y, Width, Height,
    CurrentBufferId, Lines,
    Wrap, Editable
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

let rules =
  ruleset:
    rule getTerminalWindow(Fact):
      what:
        (Window, Width, windowWidth)
        (Window, Height, windowHeight)
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
    rule cursorYChanged(Fact):
      what:
        (id, CursorX, cursorX, then = false)
        (id, CursorY, cursorY)
        (id, Lines, lines, then = false)
      then:
        if cursorY < 0:
          session.insert(id, CursorY, 0)
        elif cursorY < lines[].len:
          if cursorX > lines[cursorY].lineLen:
            session.insert(id, CursorX, lines[cursorY].lineLen)
        else:
          session.insert(id, CursorY, cursorY - 1)
    rule cursorXChanged(Fact):
      what:
        (id, CursorX, cursorX)
        (id, CursorY, cursorY, then = false)
        (id, Lines, lines)
        (id, Wrap, wrap)
      then:
        if wrap:
          if cursorX > lines[cursorY].lineLen:
            if cursorY < lines[].len - 1:
              session.insert(id, CursorY, cursorY + 1)
              session.insert(id, CursorX, 0)
            else:
              session.insert(id, CursorX, cursorX - 1)
          elif cursorX < 0:
            if cursorY > 0:
              session.insert(id, CursorY, cursorY - 1)
              session.insert(id, CursorX, lines[cursorY - 1].lineLen)
            else:
              session.insert(id, CursorX, 0)
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
        (Window, CurrentBufferId, id)
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
  session.insert(Window, Width, width)
  session.insert(Window, Height, height)

proc exitProc() {.noconv.} =
  iw.illwillDeinit()
  iw.showCursor()
  quit(0)

const text = "\nHello, world!\nI always thought that one man, the lone balladeer with the guitar, could blow a whole army off the stage if he knew what he was doing; I've seen it happen."

proc init*() =
  iw.illwillInit(fullscreen=true)
  setControlCHook(exitProc)
  iw.hideCursor()

  for r in rules.fields:
    session.add(r)

  onWindowResize(iw.terminalWidth(), iw.terminalHeight())

  let bufferId = Id.high.ord + 1

  session.insert(Window, CurrentBufferId, bufferId)
  session.insert(bufferId, CursorX, 0)
  session.insert(bufferId, CursorY, 0)
  session.insert(bufferId, ScrollX, 0)
  session.insert(bufferId, ScrollY, 0)
  var lines: RefStrings
  new lines
  lines[] = splitLinesRetainingNewline(text)
  session.insert(bufferId, Lines, lines)
  session.insert(bufferId, X, 0)
  session.insert(bufferId, Y, 0)
  session.insert(bufferId, Width, 40)
  session.insert(bufferId, Height, 5)
  session.insert(bufferId, Wrap, true)
  session.insert(bufferId, Editable, true)

proc setCharBackground(tb: var iw.TerminalBuffer, col: int, row: int, color: iw.BackgroundColor, cursor: bool) =
  if col < 0 or row < 0:
    return
  var ch = tb[col, row]
  ch.bg = color
  tb[col, row] = ch
  if cursor:
    iw.setCursorPos(tb, col, row)

proc onInput(ch: string) =
  let currentBuffer = session.query(rules.getCurrentBuffer)
  case ch:
  of "<BS>":
    if not currentBuffer.editable:
      return
    if currentBuffer.cursorX > 0:
      let
        line = currentBuffer.lines[currentBuffer.cursorY]
        newLine = line[0 ..< currentBuffer.cursorX - 1] & line[currentBuffer.cursorX ..< line.len]
      var newLines = currentBuffer.lines
      newLines[currentBuffer.cursorY] = newLine
      session.insert(currentBuffer.id, Lines, newLines)
      session.insert(currentBuffer.id, CursorX, currentBuffer.cursorX - 1)
      session.insert(currentBuffer.id, Width, currentBuffer.width) # force refresh
  of "<Del>":
    if not currentBuffer.editable:
      return
    if currentBuffer.cursorX < currentBuffer.lines[currentBuffer.cursorY].lineLen:
      let
        line = currentBuffer.lines[currentBuffer.cursorY]
        newLine = line[0 ..< currentBuffer.cursorX] & line[currentBuffer.cursorX + 1 ..< line.len]
      var newLines = currentBuffer.lines
      newLines[currentBuffer.cursorY] = newLine
      session.insert(currentBuffer.id, Lines, newLines)
      session.insert(currentBuffer.id, Width, currentBuffer.width) # force refresh
  of "<Enter>":
    if not currentBuffer.editable:
      return
    let
      line = currentbuffer.lines[currentBuffer.cursorY]
      before = line[0 ..< currentBuffer.cursorX]
      after = line[currentBuffer.cursorX ..< line.len]
      keepCursorOnLine = currentBuffer.wrap and
                         currentBuffer.cursorX == 0 and
                         currentBuffer.cursorY > 0 and
                         not strutils.endsWith(currentBuffer.lines[currentBuffer.cursorY - 1], "\n")
    var newLines: ref seq[string]
    new newLines
    newLines[] = currentBuffer.lines[0 ..< currentBuffer.cursorY]
    if keepCursorOnLine:
      newLines[newLines[].len - 1] &= "\n"
    else:
      newLines[].add(before & "\n")
    newLines[].add(after)
    newLines[].add(currentBuffer.lines[currentBuffer.cursorY + 1 ..< currentBuffer.lines[].len])
    session.insert(currentBuffer.id, Lines, newLines)
    session.insert(currentBuffer.id, Width, currentBuffer.width) # force refresh
    session.insert(currentBuffer.id, CursorX, 0)
    if not keepCursorOnLine:
      session.insert(currentBuffer.id, CursorY, currentBuffer.cursorY + 1)
  of "<Up>":
    session.insert(currentBuffer.id, CursorY, currentBuffer.cursorY - 1)
  of "<Down>":
    session.insert(currentBuffer.id, CursorY, currentBuffer.cursorY + 1)
  of "<Left>":
    session.insert(currentBuffer.id, CursorX, currentBuffer.cursorX - 1)
  of "<Right>":
    session.insert(currentBuffer.id, CursorX, currentBuffer.cursorX + 1)
  of "<Home>":
    session.insert(currentBuffer.id, CursorX, 0)
  of "<End>":
    session.insert(currentBuffer.id, CursorX, currentBuffer.lines[currentBuffer.cursorY].lineLen)

proc onInput(ch: char) =
  let currentBuffer = session.query(rules.getCurrentBuffer)
  if not currentBuffer.editable:
    return
  let
    line = currentBuffer.lines[currentBuffer.cursorY]
    newLine = line[0 ..< currentBuffer.cursorX] & $ch & line[currentBuffer.cursorX ..< line.len]
  var newLines = currentBuffer.lines
  newLines[currentBuffer.cursorY] = newLine
  session.insert(currentBuffer.id, Lines, newLines)
  session.insert(currentBuffer.id, CursorX, currentBuffer.cursorX + 1)
  session.insert(currentBuffer.id, Width, currentBuffer.width) # force refresh

proc renderBuffer(tb: var TerminalBuffer, buffer: tuple, focused: bool) =
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

  if focused:
    let
      col = buffer.x + 1 + buffer.cursorX - buffer.scrollX
      row = buffer.y + 1 + buffer.cursorY - buffer.scrollY
    setCharBackground(tb, col, row, iw.bgYellow, true)

proc tick*() =
  var key = iw.getKey()
  case key
  of iw.Key.None: discard
  else:
    let code = key.ord
    if iwToSpecials.hasKey(code):
      onInput(iwToSpecials[code])
    elif code >= 32:
      onInput(char(code))
  session.fireRules()

  let
    (windowWidth, windowHeight) = session.query(rules.getTerminalWindow)
    currentBuffer = session.query(rules.getCurrentBuffer)
    width = iw.terminalWidth()
    height = iw.terminalHeight()
  var tb = iw.newTerminalBuffer(width, height)
  if width != windowWidth or height != windowHeight:
    onWindowResize(width, height)

  renderBuffer(tb, currentBuffer, true)

  iw.display(tb)

when isMainModule:
  init()
  while true:
    tick()
    os.sleep(10)
