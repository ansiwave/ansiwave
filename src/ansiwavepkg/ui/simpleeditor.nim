from illwave as iw import `[]`, `[]=`, `==`
import pararules
from pararules/engine import Session, Vars
import json
import unicode
from ./context import nil
from nimwave import nil
from terminal import nil
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

proc simpleEditorView*(ctx: var context.Context, node: JsonNode, children: seq[JsonNode]): context.RenderProc =
  var session = init()
  if "initial-value" in node:
    setContent(session, node["initial-value"].str)
  return
    proc (ctx: var context.Context, node: JsonNode, children: seq[JsonNode]) =
      ctx = nimwave.slice(ctx, 0, 0, iw.width(ctx.tb), 3)
      let currIndex = ctx.data.focusAreas[].len
      var area: context.ViewFocusArea
      area.tb = ctx.tb
      if node.hasKey("action"):
        area.action = node["action"].str
        area.actionData = {"term": % getContent(session)}.toOrderedTable
      ctx.data.focusAreas[].add(area)
      let focused = currIndex == ctx.data.focusIndex
      if focused:
        onInput(session, ctx.data.input)

      let editor = session.query(rules.getEditor)
      nimwave.render(ctx,
        %*{
          "type": "rect",
          "children": [editor.line],
          "children-after":
            if focused:
              %* [{"type": "cursor", "x": editor.cursorX, "y": editor.cursorY}]
            else:
              %* []
          ,
          "bottom-left-focused": node["prompt"].str,
          "bottom-left": "",
          "focused": focused,
        }
      )

proc cursorView*(ctx: var context.Context, node: JsonNode, children: seq[JsonNode]) =
  let
    col = int(node["x"].num)
    row = int(node["y"].num)
  var ch = ctx.tb[col, row]
  ch.bg = iw.BackgroundColor(kind: iw.SimpleColor, simpleColor: terminal.bgYellow)
  if ch.fg == iw.ForegroundColor(kind: iw.SimpleColor, simpleColor: terminal.fgYellow):
    ch.fg = iw.ForegroundColor(kind: iw.SimpleColor, simpleColor: terminal.fgWhite)
  elif $ch.ch == "█":
    ch.fg = iw.ForegroundColor(kind: iw.SimpleColor, simpleColor: terminal.fgYellow)
  ctx.tb[col, row] = ch
  iw.setCursorPos(ctx.tb, col, row)

