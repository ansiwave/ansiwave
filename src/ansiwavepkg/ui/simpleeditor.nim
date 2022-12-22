from illwave as iw import `[]`, `[]=`, `==`
import pararules
from pararules/engine import Session, Vars
import json
import unicode
from ./context import nil
from nimwave as nw import nil
import tables

type
  Id = enum
    Editor
  Attr = enum
    CursorX, CursorY,
    Line,

schema Fact(Id, Attr):
  CursorX: int
  CursorY: int
  Line: string

type
  EditorSession* = Session[Fact, Vars[Fact]]

let rules =
  ruleset:
    rule getEditor(Fact):
      what:
        (Editor, CursorX, cursorX)
        (Editor, CursorY, cursorY)
        (Editor, Line, line)

proc getContent*(session: EditorSession): string =
  session.query(rules.getEditor).line

proc init(): EditorSession =
  result = initSession(Fact, autoFire = false)
  for r in rules.fields:
    result.add(r)
  result.insert(Editor, CursorX, 0)
  result.insert(Editor, CursorY, 0)
  result.insert(Editor, Line, "")

proc setContent(session: var EditorSession, content: string) =
  session.insert(Editor, CursorX, 0)
  session.insert(Editor, CursorY, 0)
  session.insert(Editor, Line, content)
  session.fireRules

proc onInput(session: var EditorSession, key: iw.Key, buffer: tuple): bool =
  case key:
  of iw.Key.Backspace:
    if buffer.cursorX > 0:
      let
        line = buffer.line.toRunes
        x = buffer.cursorX - 1
        newLine = $line[0 ..< x] & $line[x + 1 ..< line.len]
      session.insert(Editor, Line, newLine)
      session.insert(Editor, CursorX, buffer.cursorX - 1)
  of iw.Key.Delete:
    if buffer.cursorX < buffer.line.runeLen:
      let
        line = buffer.line.toRunes
        newLine = $line[0 ..< buffer.cursorX] & $line[buffer.cursorX + 1 ..< line.len]
      session.insert(Editor, Line, newLine)
  of iw.Key.Left:
    if buffer.cursorX > 0:
      session.insert(Editor, CursorX, buffer.cursorX - 1)
  of iw.Key.Right:
    if buffer.cursorX < buffer.line.runeLen:
      session.insert(Editor, CursorX, buffer.cursorX + 1)
  of iw.Key.Home:
    session.insert(Editor, CursorX, 0)
  of iw.Key.End:
    session.insert(Editor, CursorX, buffer.line.runeLen)
  else:
    return false
  true

proc onInput(session: var EditorSession, code: uint32, buffer: tuple): bool =
  if code < 32:
    return false
  let
    ch = cast[Rune](code)
    line = buffer.line.toRunes
    before = line[0 ..< buffer.cursorX]
    after = line[buffer.cursorX ..< line.len]
  session.insert(Editor, Line, $before & $ch & $after)
  session.insert(Editor, CursorX, buffer.cursorX + 1)
  true

proc onInput(session: var EditorSession, input: tuple[key: iw.Key, codepoint: uint32]) =
  let buffer = session.query(rules.getEditor)
  if input.key notin {iw.Key.None, iw.Key.Mouse}:
    discard onInput(session, input.key, buffer)
  elif input.codepoint != 0:
    discard onInput(session, input.codepoint, buffer)
  session.fireRules

type
  SimpleEditor* = ref object of nw.Node
    session*: EditorSession
    initialValue*: string
    action*: string
    prompt*: string
  Cursor = ref object of nw.Node
    x: int
    y: int

method mount*(node: SimpleEditor, ctx: var context.Context) =
  node.session = init()
  setContent(node.session, node.initialValue)

method render*(node: SimpleEditor, ctx: var context.Context) =
  let mnode = context.getMounted(node, ctx)
  ctx = nw.slice(ctx, 0, 0, iw.width(ctx.tb), 3)
  let currIndex = ctx.data.focusAreas[].len
  var area: context.ViewFocusArea
  area.tb = ctx.tb
  area.action = node.action
  area.actionData = {"term": % getContent(mnode.session)}.toTable
  ctx.data.focusAreas[].add(area)
  let focused = currIndex == ctx.data.focusIndex
  if focused:
    onInput(mnode.session, ctx.data.input)

  let
    editor = mnode.session.query(rules.getEditor)
    focusedRef = new bool
  focusedRef[] = focused
  context.render(
    context.Rect(
      children: nw.seq(nw.Text(str: editor.line)),
      childrenAfter: if focused: nw.seq(Cursor(x: editor.cursorX, y: editor.cursorY)) else: nw.seq(),
      bottomLeftFocused: node.prompt,
      focused: focusedRef
    ),
    ctx
  )

method render*(node: Cursor, ctx: var context.Context) =
  let
    col = int(node.x)
    row = int(node.y)
  var ch = ctx.tb[col, row]
  ch.bg = iw.bgYellow
  if ch.fg == iw.fgYellow:
    ch.fg = iw.fgWhite
  elif $ch.ch == "█":
    ch.fg = iw.fgYellow
  ctx.tb[col, row] = ch

