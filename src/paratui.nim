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
    CurrentBufferId, Lines, LineColumns,
  RefStrings = ref seq[string]

schema Fact(Id, Attr):
  CursorLine: int
  CursorColumn: int
  ScrollX: float
  ScrollY: float
  WindowLines: int
  WindowColumns: int
  CurrentBufferId: int
  Lines: RefStrings
  LineColumns: int

let rules =
  ruleset:
    rule getTerminalWindow(Fact):
      what:
        (Global, WindowColumns, windowColumns)
        (Global, WindowLines, windowLines)
    rule updateTerminalScrollX(Fact):
      what:
        (Global, WindowColumns, windowColumns)
        (id, CursorColumn, cursorColumn)
        (id, ScrollX, scrollX, then = false)
      then:
        let scrollRight = scrollX.int + windowColumns - 1
        if cursorColumn < scrollX.int:
          session.insert(id, ScrollX, cursorColumn.float)
        elif cursorColumn > scrollRight:
          session.insert(id, ScrollX, scrollX + float(cursorColumn - scrollRight))
    rule updateTerminalScrollY(Fact):
      what:
        (Global, WindowLines, windowLines)
        (id, CursorLine, cursorLine)
        (id, ScrollY, scrollY, then = false)
      then:
        let scrollBottom = scrollY.int + windowLines - 2
        if cursorLine < scrollY.int:
          session.insert(id, ScrollY, cursorLine.float)
        elif cursorLine > scrollBottom:
          session.insert(id, ScrollY, scrollY + float(cursorLine - scrollBottom))
    rule cursorLineChanged(Fact):
      what:
        (id, CursorLine, cursorLine)
        (id, CursorColumn, cursorColumn, then = false)
        (id, Lines, lines, then = false)
      cond:
        cursorLine < lines[].len
        cursorColumn > lines[cursorLine].len
      then:
        session.insert(id, CursorColumn, lines[cursorLine].len)
    rule wrapText(Fact):
      what:
        (Global, WindowColumns, windowColumns)
        (id, Lines, lines)
        (id, LineColumns, lineColumns)
      cond:
        windowColumns > 0
        lineColumns != windowColumns
      then:
        let fullLines = splitLinesRetainingNewline(strutils.join(lines[]))
        var wrapLines: seq[seq[string]]
        for line in fullLines:
          var parts: seq[string]
          var rest = line
          while true:
            if rest.lineLen > windowColumns:
              parts.add(rest[0 ..< windowColumns])
              rest = rest[windowColumns ..< rest.len]
            else:
              parts.add(rest)
              break
          wrapLines.add(parts)
        var newLines: ref seq[string]
        new newLines
        for line in wrapLines:
          newLines[].add(line)
        session.insert(id, Lines, newLines)
        session.insert(id, LineColumns, windowColumns)
    rule getCurrentBuffer(Fact):
      what:
        (Global, CurrentBufferId, id)
        (id, CursorLine, cursorLine)
        (id, CursorColumn, cursorColumn)
        (id, ScrollX, scrollX)
        (id, ScrollY, scrollY)
        (id, Lines, lines)

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
  session.insert(bufferId, ScrollX, 0f)
  session.insert(bufferId, ScrollY, 0f)
  var lines: RefStrings
  new lines
  lines[] = splitLinesRetainingNewline(text)
  session.insert(bufferId, Lines, lines)
  session.insert(bufferId, LineColumns, 0)

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
      line = currentBuffer.lines[currentBuffer.cursorLine]
      before = line[0 ..< currentBuffer.cursorColumn]
      after = line[currentBuffer.cursorColumn ..< line.len]
      newLine = before & "\n" & after
    var newLines = currentBuffer.lines
    newLines[currentBuffer.cursorLine] = newLine
    session.insert(currentBuffer.id, Lines, newLines)
    session.insert(currentBuffer.id, LineColumns, 0)
    if not (currentBuffer.cursorColumn == 0 and
            currentBuffer.cursorLine != 0 and
            not strutils.endsWith(currentBuffer.lines[currentBuffer.cursorLine - 1], "\n")):
      session.insert(currentBuffer.id, CursorLine, currentBuffer.cursorLine + 1)
    session.insert(currentBuffer.id, CursorColumn, 0)
  of "<Up>":
    if currentBuffer.cursorLine > 0:
      session.insert(currentBuffer.id, CursorLine, currentBuffer.cursorLine - 1)
  of "<Down>":
    if currentBuffer.cursorLine + 1 < currentBuffer.lines[].len:
      session.insert(currentBuffer.id, CursorLine, currentBuffer.cursorLine + 1)
  of "<Left>":
    if currentBuffer.cursorColumn > 0:
      session.insert(currentBuffer.id, CursorColumn, currentBuffer.cursorColumn - 1)
  of "<Right>":
    if currentBuffer.cursorColumn < currentBuffer.lines[currentBuffer.cursorLine].lineLen:
      session.insert(currentBuffer.id, CursorColumn, currentBuffer.cursorColumn + 1)
  of "<Home>":
    if currentBuffer.cursorColumn > 0:
      session.insert(currentBuffer.id, CursorColumn, 0)
  of "<End>":
    if currentBuffer.cursorColumn < currentBuffer.lines[currentBuffer.cursorLine].lineLen:
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
  session.insert(currentBuffer.id, LineColumns, 0)

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

  let
    lines = currentBuffer.lines[]
    scrollX = currentBuffer.scrollX.int
    scrollY = currentBuffer.scrollY.int
  var screenLine = 0
  for i in scrollY ..< lines.len:
    if screenLine >= height - 1:
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
    col = currentBuffer.cursorColumn - currentBuffer.scrollX.int
    row = currentBuffer.cursorLine - currentBuffer.scrollY.int
  setCharBackground(tb, col, row, iw.bgYellow, true)

  iw.display(tb)

when isMainModule:
  init()
  while true:
    tick()
    os.sleep(20)
