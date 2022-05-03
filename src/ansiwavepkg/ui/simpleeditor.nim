from illwave as iw import `[]`, `[]=`, `==`
import pararules
from pararules/engine import Session, Vars
import json
import unicode

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

proc init*(): EditorSession =
  result = initSession(Fact, autoFire = false)
  for r in rules.fields:
    result.add(r)
  result.insert(Editor, CursorX, 0)
  result.insert(Editor, CursorY, 0)
  result.insert(Editor, Line, "")

proc setContent*(session: var EditorSession, content: string) =
  session.insert(Editor, CursorX, 0)
  session.insert(Editor, CursorY, 0)
  session.insert(Editor, Line, content)
  session.fireRules

proc onInput*(session: var EditorSession, key: iw.Key, buffer: tuple): bool =
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

proc onInput*(session: var EditorSession, code: uint32, buffer: tuple): bool =
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

proc onInput*(session: var EditorSession, input: tuple[key: iw.Key, codepoint: uint32]) =
  let buffer = session.query(rules.getEditor)
  if input.codepoint != 0:
    discard onInput(session, input.codepoint, buffer)
  elif input.key notin {iw.Key.None, iw.Key.Mouse}:
    discard onInput(session, input.key, buffer) or onInput(session, input.key.ord.uint32, buffer)
  session.fireRules

proc toJson*(session: EditorSession, prompt: string, action: string): JsonNode =
  let editor = session.query(rules.getEditor)
  %*{
    "type": "rect",
    "children": [editor.line],
    "children-after": [
      {"type": "cursor", "x": editor.cursorX, "y": editor.cursorY},
    ],
    "bottom-left-focused": prompt,
    "bottom-left": "",
    "action": action,
    "action-data": {},
  }

