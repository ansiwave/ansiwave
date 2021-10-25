from ./illwill as iw import `[]`, `[]=`
import ./constants
import unicode
from ./codes import stripCodes
import json
import tables
from wavecorepkg/db/entities import nil
from wavecorepkg/client import nil
from strutils import format
from os import joinPath

type
  ComponentKind = enum
    Post,
  Component* = object
    case kind: ComponentKind
    of Post:
      main: client.ChannelValue[client.Response]
      replies: client.ChannelValue[seq[entities.Post]]

const
  dbFilename* = "board.db"
  staticFileDir = "tests".joinPath("bbs")
  dbPath = staticFileDir.joinPath(dbFilename)
  ansiwavesDir = "ansiwaves"

proc initPost*(c: client.Client, id: int): Component =
  result = Component(kind: Post)
  result.main = client.query(c, ansiwavesDir.joinPath($id & ".ansiwavez"))
  result.replies = client.queryPostChildren(c, dbFilename, id)

proc toJson*(post: entities.Post): JsonNode =
  %*[
    {
      "type": "rect",
      "children": strutils.splitLines(post.body.uncompressed)
    },
    {
      "type": "button",
      "text":
        if post.reply_count == 0:
          "Reply"
        elif post.reply_count == 1:
          "1 Reply"
        else:
          $post.reply_count & " Replies"
      ,
      "action": "show-replies",
      "action-data": {"id": post.id},
    },
  ]

proc toJson*(posts: seq[entities.Post]): JsonNode =
  result = JsonNode(kind: JArray)
  for post in posts:
    result.elems.add(toJson(post))

proc toJson*(comp: var Component, finishedLoading: var bool): JsonNode =
  case comp.kind:
  of Post:
    client.get(comp.main)
    client.get(comp.replies)
    finishedLoading = comp.main.ready and comp.replies.ready
    %*[
      if not comp.main.ready:
        %"Loading..."
      elif comp.main.value.kind == client.Error:
        %"Failed to load!"
      else:
        %*{
          "type": "rect",
          "children": strutils.splitLines(comp.main.value.valid.body)
        }
      ,
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
  y += 1
  codes.write(tb, x, y, $runes)

proc render*(tb: var iw.TerminalBuffer, node: JsonNode, x: int, y: var int, key: iw.Key, focusIndex: int, blocks: var seq[tuple[top: int, bottom: int]], action: var tuple[actionName: string, actionData: OrderedTable[string, JsonNode]])

proc render*(tb: var iw.TerminalBuffer, node: OrderedTable[string, JsonNode], x: int, y: var int, key: iw.Key, focusIndex: int, blocks: var seq[tuple[top: int, bottom: int]], action: var tuple[actionName: string, actionData: OrderedTable[string, JsonNode]]) =
  let
    isFocused = focusIndex == blocks.len
    yStart = y
  case node["type"].str:
  of "rect":
    for child in node["children"]:
      render(tb, child, x + 1, y, key, focusIndex, blocks, action)
    y += 1
    iw.drawRect(tb, x, yStart, x + editorWidth + 1, y, doubleStyle = isFocused)
    y += 1
  of "button":
    let xStart = max(x + 1, editorWidth + 1 - node["text"].str.len)
    # handle input
    if key == iw.Key.Mouse:
      let info = iw.getMouse()
      if info.button == iw.MouseButton.mbLeft and info.action == iw.MouseButtonAction.mbaPressed:
        if info.x >= xStart and
            info.x < xStart + node["text"].str.stripCodes.len and
            info.y >= yStart and
            info.y <= yStart + 2:
          action = (node["action"].str, node["action-data"].fields)
    elif key == iw.Key.Enter and isFocused:
      action = (node["action"].str, node["action-data"].fields)
    render(tb, node["text"].str, xStart, y, key)
    y += 1
    iw.drawRect(tb, xStart - 1, yStart, editorWidth + 1, y, doubleStyle = isFocused)
    y += 1
  blocks.add((top: yStart, bottom: y))

proc render*(tb: var iw.TerminalBuffer, node: JsonNode, x: int, y: var int, key: iw.Key, focusIndex: int, blocks: var seq[tuple[top: int, bottom: int]], action: var tuple[actionName: string, actionData: OrderedTable[string, JsonNode]]) =
  case node.kind:
  of JString:
    render(tb, node.str, x, y, key)
  of JObject:
    render(tb, node.fields, x, y, key, focusIndex, blocks, action)
  of JArray:
    for item in node.elems:
      render(tb, item, x, y, key, focusIndex, blocks, action)
  else:
    raise newException(Exception, "Unhandled JSON type")

