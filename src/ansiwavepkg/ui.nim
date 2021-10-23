from illwill as iw import `[]`, `[]=`
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
  Component = object of RootObj
    focusIndex: int
  Post* = ref object of Component
    main: client.ChannelValue[client.Response]
    replies: client.ChannelValue[seq[entities.Post]]

const
  dbFilename* = "board.db"
  staticFileDir = "tests".joinPath("bbs")
  dbPath = staticFileDir.joinPath(dbFilename)
  ansiwavesDir = "ansiwaves"
  actions = {
    "show-replies": proc (data: OrderedTable[string, JsonNode]) =
      # TODO: do something
      discard
  }.toTable

proc init*[Post](c: client.Client, id: int): Post =
  new result
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

proc toJson*(comp: var Post): JsonNode =
  client.get(comp.main)
  client.get(comp.replies)
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

proc render*(tb: var iw.TerminalBuffer, node: JsonNode, x: int, y: var int, key: iw.Key, focusIndex: int, currFocusIndex: var int)

proc render*(tb: var iw.TerminalBuffer, node: OrderedTable[string, JsonNode], x: int, y: var int, key: iw.Key, focusIndex: int, currFocusIndex: var int) =
  let isFocused = focusIndex == currFocusIndex
  currFocusIndex += 1
  case node["type"].str:
  of "rect":
    let yStart = y
    for child in node["children"]:
      render(tb, child, x + 1, y, key, focusIndex, currFocusIndex)
    y += 1
    iw.drawRect(tb, x, yStart, editorWidth, y, doubleStyle = isFocused)
    y += 1
  of "button":
    let
      xStart = max(x + 1, editorWidth - node["text"].str.len)
      yStart = y
    # handle input
    if key == iw.Key.Mouse:
      let info = iw.getMouse()
      if info.button == iw.MouseButton.mbLeft and info.action == iw.MouseButtonAction.mbaPressed:
        if info.x >= xStart and
            info.x < xStart + node["text"].str.stripCodes.len and
            info.y >= yStart and
            info.y <= yStart + 2:
          actions[node["action"].str](node["action-data"].fields)
    render(tb, node["text"].str, xStart, y, key)
    y += 1
    iw.drawRect(tb, xStart - 1, yStart, editorWidth, y, doubleStyle = isFocused)
    y += 1

proc render*(tb: var iw.TerminalBuffer, node: JsonNode, x: int, y: var int, key: iw.Key, focusIndex: int, currFocusIndex: var int) =
  case node.kind:
  of JString:
    render(tb, node.str, x, y, key)
  of JObject:
    render(tb, node.fields, x, y, key, focusIndex, currFocusIndex)
  of JArray:
    for item in node.elems:
      render(tb, item, x, y, key, focusIndex, currFocusIndex)
  else:
    raise newException(Exception, "Unhandled JSON type")

proc render*(tb: var iw.TerminalBuffer, post: var Post, key: iw.Key) =
  var
    y = 0
    currFocusIndex = 0
  case key:
  of iw.Key.Up:
    if post.focusIndex > 0:
      post.focusIndex -= 1
  of iw.Key.Down:
    post.focusIndex = post.focusIndex + 1
  else:
    discard
  render(tb, toJson(post), 0, y, key, post.focusIndex, currFocusIndex)
  if post.focusIndex > currFocusIndex:
    post.focusIndex = currFocusIndex

