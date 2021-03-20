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
    Global
  Attr* = enum
    CursorLine, CursorColumn,
    ScrollX, ScrollY,
    WindowColumns, WindowLines,
    CurrentBufferId, Lines,
    BufferLines, BufferColumns,
    Wrap
  RefStrings = ref seq[string]

schema Fact(Id, Attr):
  CursorLine: int
  CursorColumn: int
  ScrollX: int
  ScrollY: int
  WindowLines: int
  WindowColumns: int
  CurrentBufferId: int
  Lines: RefStrings
  BufferLines: int
  BufferColumns: int
  Wrap: bool

let rules =
  ruleset:
    rule getTerminalWindow(Fact):
      what:
        (Global, WindowColumns, windowColumns)
        (Global, WindowLines, windowLines)
    rule updateTerminalScrollX(Fact):
      what:
        (id, BufferColumns, bufferColumns)
        (id, CursorColumn, cursorColumn)
        (id, ScrollX, scrollX, then = false)
        (id, Wrap, wrap)
      cond:
        wrap == false
        cursorColumn >= 0
      then:
        let scrollRight = scrollX + bufferColumns - 1
        if cursorColumn < scrollX:
          session.insert(id, ScrollX, cursorColumn)
        elif cursorColumn > scrollRight:
          session.insert(id, ScrollX, scrollX + (cursorColumn - scrollRight))
    rule updateTerminalScrollY(Fact):
      what:
        (id, BufferLines, bufferLines)
        (id, CursorLine, cursorLine)
        (id, Lines, lines)
        (id, ScrollY, scrollY, then = false)
      cond:
        cursorLine >= 0
      then:
        let scrollBottom = scrollY + bufferLines - 1
        if cursorLine < scrollY:
          session.insert(id, ScrollY, cursorLine)
        elif cursorLine > scrollBottom and cursorLine < lines[].len:
          session.insert(id, ScrollY, scrollY + (cursorLine - scrollBottom))
    rule cursorLineChanged(Fact):
      what:
        (id, CursorLine, cursorLine)
        (id, CursorColumn, cursorColumn, then = false)
        (id, Lines, lines, then = false)
      then:
        if cursorLine < 0:
          session.insert(id, CursorLine, 0)
        elif cursorLine < lines[].len:
          if cursorColumn > lines[cursorLine].lineLen:
            session.insert(id, CursorColumn, lines[cursorLine].lineLen)
        else:
          session.insert(id, CursorLine, cursorLine - 1)
    rule cursorColumnChanged(Fact):
      what:
        (id, CursorLine, cursorLine, then = false)
        (id, CursorColumn, cursorColumn)
        (id, Lines, lines)
        (id, Wrap, wrap)
      then:
        if wrap:
          if cursorColumn > lines[cursorLine].lineLen:
            if cursorLine < lines[].len - 1:
              session.insert(id, CursorLine, cursorLine + 1)
              session.insert(id, CursorColumn, 0)
            else:
              session.insert(id, CursorColumn, cursorColumn - 1)
          elif cursorColumn < 0:
            if cursorLine > 0:
              session.insert(id, CursorLine, cursorLine - 1)
              session.insert(id, CursorColumn, lines[cursorLine - 1].lineLen)
            else:
              session.insert(id, CursorColumn, 0)
        else:
          if cursorColumn > lines[cursorLine].lineLen:
            session.insert(id, CursorColumn, lines[cursorLine].lineLen)
          elif cursorColumn < 0:
            session.insert(id, CursorColumn, 0)
    rule wrapText(Fact):
      what:
        (id, Wrap, wrap)
        (id, Lines, lines, then = false)
        (id, BufferColumns, bufferColumns)
      cond:
        wrap
        bufferColumns > 0
      then:
        let
          fullLines = splitLinesRetainingNewline(strutils.join(lines[]))
          lineColumns = bufferColumns - 1
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
        (id, CursorLine, cursorLine)
        (id, CursorColumn, cursorColumn)
        (id, ScrollX, scrollX)
        (id, ScrollY, scrollY)
        (id, Lines, lines)
        (id, Wrap, wrap)
        (id, BufferLines, bufferLines)
        (id, BufferColumns, bufferColumns)

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
  session.insert(Global, WindowColumns, width)
  session.insert(Global, WindowLines, height)

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

  session.insert(Global, CurrentBufferId, bufferId)
  session.insert(bufferId, CursorLine, 0)
  session.insert(bufferId, CursorColumn, 0)
  session.insert(bufferId, ScrollX, 0)
  session.insert(bufferId, ScrollY, 0)
  var lines: RefStrings
  new lines
  lines[] = splitLinesRetainingNewline(text)
  session.insert(bufferId, Lines, lines)
  session.insert(bufferId, BufferLines, 5)
  session.insert(bufferId, BufferColumns, 40)
  session.insert(bufferId, Wrap, true)

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
    if currentBuffer.cursorColumn > 0:
      let
        line = currentBuffer.lines[currentBuffer.cursorLine]
        newLine = line[0 ..< currentBuffer.cursorColumn - 1] & line[currentBuffer.cursorColumn ..< line.len]
      var newLines = currentBuffer.lines
      newLines[currentBuffer.cursorLine] = newLine
      session.insert(currentBuffer.id, Lines, newLines)
      session.insert(currentBuffer.id, CursorColumn, currentBuffer.cursorColumn - 1)
  of "<Del>":
    if currentBuffer.cursorColumn < currentBuffer.lines[currentBuffer.cursorLine].lineLen:
      let
        line = currentBuffer.lines[currentBuffer.cursorLine]
        newLine = line[0 ..< currentBuffer.cursorColumn] & line[currentBuffer.cursorColumn + 1 ..< line.len]
      var newLines = currentBuffer.lines
      newLines[currentBuffer.cursorLine] = newLine
      session.insert(currentBuffer.id, Lines, newLines)
  of "<Enter>":
    let
      line = currentbuffer.lines[currentBuffer.cursorLine]
      before = line[0 ..< currentBuffer.cursorColumn]
      after = line[currentBuffer.cursorColumn ..< line.len]
      keepCursorOnLine = currentBuffer.wrap and
                         currentBuffer.cursorColumn == 0 and
                         currentBuffer.cursorLine > 0 and
                         not strutils.endsWith(currentBuffer.lines[currentBuffer.cursorLine - 1], "\n")
    var newLines: ref seq[string]
    new newLines
    newLines[] = currentBuffer.lines[0 ..< currentBuffer.cursorLine]
    if keepCursorOnLine:
      newLines[newLines[].len - 1] &= "\n"
    else:
      newLines[].add(before & "\n")
    if after.len > 0:
      newLines[].add(after)
    newLines[].add(currentBuffer.lines[currentBuffer.cursorLine + 1 ..< currentBuffer.lines[].len])
    session.insert(currentBuffer.id, Lines, newLines)
    session.insert(currentBuffer.id, BufferColumns, currentBuffer.bufferColumns) # force refresh
    session.insert(currentBuffer.id, CursorColumn, 0)
    if not keepCursorOnLine:
      session.insert(currentBuffer.id, CursorLine, currentBuffer.cursorLine + 1)
  of "<Up>":
    session.insert(currentBuffer.id, CursorLine, currentBuffer.cursorLine - 1)
  of "<Down>":
    session.insert(currentBuffer.id, CursorLine, currentBuffer.cursorLine + 1)
  of "<Left>":
    session.insert(currentBuffer.id, CursorColumn, currentBuffer.cursorColumn - 1)
  of "<Right>":
    session.insert(currentBuffer.id, CursorColumn, currentBuffer.cursorColumn + 1)
  of "<Home>":
    session.insert(currentBuffer.id, CursorColumn, 0)
  of "<End>":
    session.insert(currentBuffer.id, CursorColumn, currentBuffer.lines[currentBuffer.cursorLine].lineLen)

proc onInput(ch: char) =
  let
    currentBuffer = session.query(rules.getCurrentBuffer)
    line = currentBuffer.lines[currentBuffer.cursorLine]
    newLine = line[0 ..< currentBuffer.cursorColumn] & $ch & line[currentBuffer.cursorColumn ..< line.len]
  var newLines = currentBuffer.lines
  newLines[currentBuffer.cursorLine] = newLine
  session.insert(currentBuffer.id, Lines, newLines)
  session.insert(currentBuffer.id, CursorColumn, currentBuffer.cursorColumn + 1)
  session.insert(currentBuffer.id, BufferColumns, currentBuffer.bufferColumns) # force refresh

proc renderBuffer(tb: var TerminalBuffer, buffer: tuple) =
  let
    lines = buffer.lines[]
    scrollX = buffer.scrollX
    scrollY = buffer.scrollY
  var screenLine = 0
  for i in scrollY ..< lines.len:
    if screenLine > buffer.bufferLines - 1:
      break
    var line = lines[i][0 ..< lines[i].lineLen]
    if scrollX < line.lineLen:
      if scrollX > 0:
        line = line[scrollX ..< line.lineLen]
    else:
      line = ""
    iw.write(tb, 0, screenLine, line)
    screenLine += 1

  let
    col = buffer.cursorColumn - buffer.scrollX
    row = buffer.cursorLine - buffer.scrollY
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
    (windowColumns, windowLines) = session.query(rules.getTerminalWindow)
    currentBuffer = session.query(rules.getCurrentBuffer)
    width = iw.terminalWidth()
    height = iw.terminalHeight()
  var tb = iw.newTerminalBuffer(width, height)
  if width != windowColumns or height != windowLines:
    onWindowResize(width, height)

  renderBuffer(tb, currentBuffer)

  iw.display(tb)

when isMainModule:
  init()
  while true:
    tick()
    os.sleep(5)
