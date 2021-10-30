import pararules
from pararules/engine import Session, Vars
import json

type
  Id = enum
    Editor, Errors, Tutorial, Publish,
  Attr = enum
    CursorX, CursorY,
    ScrollX, ScrollY,

schema Fact(Id, Attr):
  CursorX: int
  CursorY: int
  ScrollX: int
  ScrollY: int

type
  EditorSession* = Session[Fact, Vars[Fact]]

let rules =
  ruleset:
    rule getEditor(Fact):
      what:
        (Editor, CursorX, cursorX)
        (Editor, CursorY, cursorY)
        (Editor, ScrollX, cursorX)
        (Editor, ScrollY, cursorY)

proc init*(): EditorSession =
  result = initSession(Fact, autoFire = false)
  for r in rules.fields:
    result.add(r)
  result.insert(Editor, CursorX, 0)
  result.insert(Editor, CursorY, 0)
  result.insert(Editor, ScrollX, 0)
  result.insert(Editor, ScrollY, 0)

proc toJson*(session: EditorSession): JsonNode =
  %*{
    "type": "rect",
    "children": [""],
    "top-left": "Write a reply",
    "top-left-focused": "Press Enter to send, or Esc to use the full editor",
  }
