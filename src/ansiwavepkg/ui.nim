from ./illwill as iw import `[]`, `[]=`
import ./constants
import unicode
from ./codes import stripCodes
import json
import tables, sets
from wavecorepkg/db/entities import nil
from wavecorepkg/client import nil
from strutils import format
from os import joinPath
from ./ui/editor import nil

type
  ComponentKind = enum
    Post,
  Component* = object
    case kind: ComponentKind
    of Post:
      post: client.ChannelValue[client.Response]
      replies: client.ChannelValue[seq[entities.Post]]
      replyEditor: editor.EditorSession
  ViewFocusArea* = tuple[top: int, bottom: int, left: int, right: int, action: string, actionData: OrderedTable[string, JsonNode]]

const
  dbFilename* = "board.db"
  staticFileDir = "tests".joinPath("bbs")
  dbPath = staticFileDir.joinPath(dbFilename)
  ansiwavesDir = "ansiwaves"

proc initPost*(c: client.Client, id: int): Component =
  result = Component(kind: Post)
  result.post = client.query(c, ansiwavesDir.joinPath($id & ".ansiwavez"))
  result.replies = client.queryPostChildren(c, dbFilename, id)
  result.replyEditor = editor.init()

proc toJson*(post: entities.Post): JsonNode =
  %*{
    "type": "rect",
    "children": strutils.splitLines(post.body.uncompressed),
    "top-right":
      if post.reply_count == 1:
        "1 reply"
      else:
        $post.reply_count & " replies"
    ,
    "action": "show-replies",
    "action-data": {"id": post.id},
  }

proc toJson*(posts: seq[entities.Post]): JsonNode =
  result = JsonNode(kind: JArray)
  for post in posts:
    result.elems.add(toJson(post))

proc toJson*(comp: var Component, finishedLoading: var bool): JsonNode =
  case comp.kind:
  of Post:
    client.get(comp.post)
    client.get(comp.replies)
    finishedLoading = comp.post.ready and comp.replies.ready
    %*[
      if not comp.post.ready:
        %"Loading..."
      elif comp.post.value.kind == client.Error:
        %"Failed to load!"
      else:
        %*{
          "type": "rect",
          "children": strutils.splitLines(comp.post.value.valid.body)
        }
      ,
      editor.toJson(comp.replyEditor),
      "", # spacer
      if not comp.replies.ready:
        %"Loading replies"
      elif comp.replies.value.kind == client.Error:
        %"Failed to load replies!"
      else:
        if comp.replies.value.valid.len == 0:
          %"No replies"
        else:
          toJson(comp.replies.value.valid)
    ]

proc render*(tb: var iw.TerminalBuffer, node: string, x: int, y: var int, key: iw.Key) =
  var runes = node.toRunes
  codes.deleteAfter(runes, editorWidth - 1)
  codes.write(tb, x, y, $runes)
  y += 1

proc render*(tb: var iw.TerminalBuffer, node: JsonNode, x: int, y: var int, key: iw.Key, focusIndex: int, areas: var seq[ViewFocusArea])

proc render*(tb: var iw.TerminalBuffer, node: OrderedTable[string, JsonNode], x: int, y: var int, key: iw.Key, focusIndex: int, areas: var seq[ViewFocusArea]) =
  let
    isFocused = focusIndex == areas.len
    yStart = y
    xEnd = x + editorWidth + 1
    nodeType = node["type"].str
  var xStart = x
  case nodeType:
  of "rect":
    y += 1
    for child in node["children"]:
      render(tb, child, x + 1, y, key, focusIndex, areas)
    iw.drawRect(tb, xStart, yStart, xEnd, y, doubleStyle = isFocused)
    if node.hasKey("children-after"):
      for child in node["children-after"]:
        var y = yStart + 1
        render(tb, child, x + 1, y, key, focusIndex, areas)
    if node.hasKey("top-left-focused") and isFocused:
      iw.write(tb, x + 1, yStart, node["top-left-focused"].str)
    elif node.hasKey("top-left"):
      iw.write(tb, x + 1, yStart, node["top-left"].str)
    if node.hasKey("top-right-focused") and isFocused:
      iw.write(tb, xEnd - node["top-right-focused"].str.runeLen, yStart, node["top-right-focused"].str)
    elif node.hasKey("top-right"):
      iw.write(tb, xEnd - node["top-right"].str.runeLen, yStart, node["top-right"].str)
    y += 1
  of "button":
    xStart = max(x, editorWidth - node["text"].str.len)
    y += 1
    render(tb, node["text"].str, xStart, y, key)
    iw.drawRect(tb, xStart - 1, yStart, xEnd, y, doubleStyle = isFocused)
    y += 1
  of "cursor":
    if isFocused:
      let
        col = int(x + node["x"].num)
        row = int(y + node["y"].num)
      var ch = tb[col, row]
      ch.bg = iw.bgYellow
      if ch.fg == iw.fgYellow:
        ch.fg = iw.fgWhite
      elif $ch.ch == "█":
        ch.fg = iw.fgYellow
      tb[col, row] = ch
      iw.setCursorPos(tb, col, row)
  const focusables = ["rect", "button"].toHashSet
  if nodeType in focusables:
    var area: ViewFocusArea
    area.top = yStart
    area.bottom = y
    area.left = xStart
    area.right = xEnd
    if node.hasKey("action"):
      area.action = node["action"].str
      area.actionData = node["action-data"].fields
    areas.add(area)

proc render*(tb: var iw.TerminalBuffer, node: JsonNode, x: int, y: var int, key: iw.Key, focusIndex: int, areas: var seq[ViewFocusArea]) =
  case node.kind:
  of JString:
    render(tb, node.str, x, y, key)
  of JObject:
    render(tb, node.fields, x, y, key, focusIndex, areas)
  of JArray:
    for item in node.elems:
      render(tb, item, x, y, key, focusIndex, areas)
  else:
    raise newException(Exception, "Unhandled JSON type")

