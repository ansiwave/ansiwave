from illwill as iw import `[]`, `[]=`
from wavecorepkg/db/vfs import nil
from wavecorepkg/db/entities import nil
from wavecorepkg/client import nil
from os import joinPath
from strutils import format
import ./constants
import unicode
from ./codes import nil
import json
import tables

const
  port = 3000
  address = "http://localhost:" & $port
  dbFilename* = "board.db"
  ansiwavesDir* = "ansiwaves"
  staticFileDir = "tests".joinPath("bbs")
  dbPath = staticFileDir.joinPath(dbFilename)

type
  Post = object
    main: client.ChannelValue[client.Response]
    replies: client.ChannelValue[seq[entities.Post]]

proc init*[Post](c: client.Client, id: int): Post =
  result.main = client.query(c, ansiwavesDir.joinPath($id & ".ansiwavez"))
  result.replies = client.queryPostChildren(c, dbFilename, id)

proc render*(tb: var iw.TerminalBuffer, node: JsonNode, x: int, y: var int)

proc render*(post: entities.Post): JsonNode =
  %*{
    "type": "rect",
    "children": strutils.splitLines(post.body.uncompressed)
  }

proc render*(posts: seq[entities.Post]): JsonNode =
  result = JsonNode(kind: JArray)
  for post in posts:
    result.elems.add(render(post))

proc render*(comp: var Post): JsonNode =
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
        render(comp.replies.value.valid)
  ]

proc render*(tb: var iw.TerminalBuffer, node: string, x: int, y: var int) =
  var runes = node.toRunes
  codes.deleteAfter(runes, editorWidth - 1)
  y += 1
  codes.write(tb, x, y, $runes)

proc render*(tb: var iw.TerminalBuffer, node: OrderedTable[string, JsonNode], x: int, y: var int) =
  case node["type"].str:
  of "rect":
    let
      xStart = x
      yStart = y
    for child in node["children"]:
      render(tb, child, x + 1, y)
    y += 1
    iw.drawRect(tb, xStart, yStart, editorWidth, y, doubleStyle = false)
    y += 1

proc render*(tb: var iw.TerminalBuffer, node: JsonNode, x: int, y: var int) =
  case node.kind:
  of JString:
    render(tb, node.str, x, y)
  of JObject:
    render(tb, node.fields, x, y)
  of JArray:
    for item in node.elems:
      render(tb, item, x, y)
  else:
    raise newException(Exception, "Unhandled JSON type")

proc render*(tb: var iw.TerminalBuffer, post: var Post) =
  var y = 0
  render(tb, render(post), 0, y)

proc renderBBS*() =
  vfs.readUrl = "http://localhost:" & $port & "/" & dbFilename
  vfs.register()
  var c = client.initClient(address)
  client.start(c)
  var post = init[Post](c, 1)
  while true:
    let
      width = iw.terminalWidth()
      height = iw.terminalHeight()
    var tb = iw.newTerminalBuffer(width, height)
    render(tb, post)
    # display and sleep
    iw.display(tb)
    os.sleep(sleepMsecs)

