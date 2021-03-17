import illwill as iw
import tables
import pararules
from os import nil

#import paratuipkg/ansi
#const content = staticRead("../luke_and_yoda.ans")
#print(ansiToUtf8(content))

type
  Id* = enum
    Global
  Attr* = enum
    CursorLine, CursorColumn,
    ScrollX, ScrollY,
    WindowColumns, WindowLines,
    CurrentBufferId,

schema Fact(Id, Attr):
  CursorLine: int
  CursorColumn: int
  ScrollX: float
  ScrollY: float
  WindowLines: int
  WindowColumns: int
  CurrentBufferId: int

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
    rule getCurrentBuffer(Fact):
      what:
        (Global, CurrentBufferId, id)
        (id, CursorLine, cursorLine)
        (id, CursorColumn, cursorColumn)
        (id, ScrollX, scrollX)
        (id, ScrollY, scrollY)

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

proc setCharBackground(tb: var iw.TerminalBuffer, col: int, row: int, color: iw.BackgroundColor, cursor: bool) =
  if col < 0 or row < 0:
    return
  var ch = tb[col, row]
  ch.bg = color
  tb[col, row] = ch
  if cursor:
    iw.setCursorPos(tb, col, row)

proc onInput(ch: string) =
  discard

proc tick*() =
  var key = iw.getKey()
  case key
  of iw.Key.None: discard
  else:
    let code = key.ord
    if iwToSpecials.hasKey(code):
      onInput(iwToSpecials[code])
    elif code >= 32:
      onInput($ char(code))
  session.fireRules()

  let
    (windowColumns, windowLines) = session.query(rules.getTerminalWindow)
    currentBuffer = session.query(rules.getCurrentBuffer)
    width = iw.terminalWidth()
    height = iw.terminalHeight()
  var tb = iw.newTerminalBuffer(width, height)
  if width != windowColumns or height != windowLines:
    onWindowResize(width, height)

  iw.write(tb, 0, 0, "Hello, world!")
  let
    col = currentBuffer.cursorColumn - currentBuffer.scrollX.int
    row = currentBuffer.cursorLine - currentBuffer.scrollY.int
  setCharBackground(tb, col, row, iw.bgYellow, true)

  iw.display(tb)

when isMainModule:
  try:
    init()
    while true:
      tick()
      os.sleep(20)
  except Exception as e:
    iw.illwillDeinit()
    iw.showCursor()
    raise e
