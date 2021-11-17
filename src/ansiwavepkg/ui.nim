from ./illwill as iw import `[]`, `[]=`
import ./constants
import unicode
from ./codes import stripCodes
import json
import tables, sets
from wavecorepkg/db/entities import nil
from wavecorepkg/client import nil
from strutils import format
from os import `/`
from ./ui/editor import nil
from ./ui/navbar import nil
from ./crypto import nil
from ./storage import nil
from wavecorepkg/paths import nil

type
  ComponentKind* = enum
    Post, User, Editor, Login, Logout,
  Component* = ref object
    case kind*: ComponentKind
    of Post:
      sig: string
      postContent: client.ChannelValue[client.Response]
      replies: client.ChannelValue[seq[entities.Post]]
    of User:
      key: string
      userContent: client.ChannelValue[client.Response]
      userReplies: client.ChannelValue[seq[entities.Post]]
    of Editor:
      headers*: string
      session*: editor.EditorSession
      request*: client.ChannelValue[client.Response]
    of Login, Logout:
      discard
  ViewFocusArea* = tuple[top: int, bottom: int, left: int, right: int, action: string, actionData: OrderedTable[string, JsonNode]]

proc refresh*(clnt: client.Client, comp: Component) =
  case comp.kind:
  of Post:
    comp.postContent = client.query(clnt, paths.boardsDir / paths.sysopPublicKey / paths.ansiwavesDir / $comp.sig & ".ansiwavez")
    comp.replies = client.queryPostChildren(clnt, paths.boardsDir / paths.sysopPublicKey / paths.dbFilename, comp.sig)
  of User:
    comp.userContent = client.query(clnt, paths.boardsDir / paths.sysopPublicKey / paths.ansiwavesDir / $comp.key & ".ansiwavez")
    comp.userReplies = client.queryPostChildren(clnt, paths.boardsDir / paths.sysopPublicKey / paths.dbFilename, comp.key)
  of Editor, Login, Logout:
    discard

proc initPost*(clnt: client.Client, sig: string): Component =
  result = Component(kind: Post, sig: sig)
  refresh(clnt, result)

proc initUser*(clnt: client.Client, key: string): Component =
  result = Component(kind: User, key: key)
  refresh(clnt, result)

proc initEditor*(width: int, height: int, sig: string, headers: JsonNode): Component =
  result = Component(kind: Editor)
  for header in headers:
    result.headers &= header.str & "\n"
  result.session = editor.init(editor.Options(bbsMode: true, sig: sig), width, height - navbar.height)

proc initLogin*(): Component =
  Component(kind: Login)

proc initLogout*(): Component =
  Component(kind: Logout)

proc toJson*(post: entities.Post): JsonNode =
  const maxLines = int(editorWidth / 2f)
  let
    replies =
      if post.reply_count == 1:
        "1 reply"
      else:
        $post.reply_count & " replies"
    lines = strutils.splitLines(post.content.value.uncompressed)
  %*{
    "type": "rect",
    "children": if lines.len > maxLines: lines[0 ..< maxLines] else: lines,
    "top-right": replies,
    "bottom-left": if lines.len > maxLines: "see more" else: "",
    "action": "show-replies",
    "action-data": {"sig": post.content.sig},
    "action-accessible-text": replies,
  }

proc toJson*(posts: seq[entities.Post]): JsonNode =
  result = JsonNode(kind: JArray)
  for post in posts:
    result.elems.add(toJson(post))

proc toJson*(comp: Component, finishedLoading: var bool): JsonNode =
  case comp.kind:
  of Post:
    client.get(comp.postContent)
    client.get(comp.replies)
    finishedLoading = comp.postContent.ready and comp.replies.ready
    %*[
      if not comp.postContent.ready:
        %"loading..."
      elif comp.postContent.value.kind == client.Error:
        %"failed to load post"
      else:
        %*{
          "type": "rect",
          "children": strutils.splitLines(comp.postContent.value.valid.body),
        }
      ,
      {
        "type": "button",
        "text": "write a post",
        "action": "show-editor",
        "action-data": {
          "sig": comp.sig & ".new",
          "headers": [
            "/head.key " & crypto.pubKey,
            "/head.algo " & crypto.algorithm,
            "/head.parent " & comp.sig,
            "/head.last-sig",
            "/head.board " & paths.sysopPublicKey,
          ],
        },
      },
      "", # spacer
      if not comp.replies.ready:
        %"loading posts"
      elif comp.replies.value.kind == client.Error:
        %"failed to load replies"
      else:
        if comp.replies.value.valid.len == 0:
          %"no posts"
        else:
          toJson(comp.replies.value.valid)
    ]
  of User:
    client.get(comp.userContent)
    client.get(comp.userReplies)
    finishedLoading = comp.userContent.ready and comp.userReplies.ready
    %*[
      if not comp.userContent.ready:
        %"loading..."
      elif comp.userContent.value.kind == client.Error:
        %""
      else:
        %*{
          "type": "rect",
          "children": strutils.splitLines(comp.userContent.value.valid.body),
        }
      ,
      if comp.key == crypto.pubKey:
        %* {
          "type": "button",
          "align": "left",
          "text": "edit header",
          "action": "edit-user",
          "action-data": {"key": comp.key & ".edit"},
        }
      else:
        %""
      ,
      "", # spacer
      if not comp.userReplies.ready:
        %"loading posts"
      elif comp.userReplies.value.kind == client.Error:
        %"failed to load posts"
      else:
        if comp.userReplies.value.valid.len == 0:
          %"no posts"
        else:
          toJson(comp.userReplies.value.valid)
    ]
  of Editor:
    finishedLoading = true
    %*{
      "type": "editor",
      "action": "edit",
      "action-data": {},
    }
  of Login:
    finishedLoading = true
    %*[
      "",
      "If you don't have an account, create one by downloading your key.",
      "You will need this to login later so keep it somewhere safe:",
      when defined(emscripten):
        %* {
          "type": "button",
          "text": "download login key",
          "action": "create-user",
          "action-data": {},
        }
      else:
        %* {
          "type": "button",
          "text": "create account",
          "action": "create-user",
          "action-data": {},
        }
      ,
      "",
      when defined(emscripten):
        %* [
          "If you already have an account, add your key:",
          {
            "type": "button",
            "text": "add existing login key",
            "action": "add-user",
            "action-data": {},
          },
        ]
      else:
        %* [
          "If you already have an account, copy your login key",
          "into the data directory:",
          "",
          "cp path/to/login-key.png " & storage.dataDir & "/.",
          "",
          "Then, rerun ansiwave and you will be logged in.",
        ]
      ,
    ]
  of Logout:
    finishedLoading = true
    when defined(emscripten):
      %*[
        "",
        "Are you sure you want to logout?",
        "If you don't have a copy of your login key somewhere,",
        "you will never be able to login again!",
        {
          "type": "button",
          "text": "cancel",
          "action": "go-back",
          "action-data": {},
        },
        {
          "type": "button",
          "text": "continue logout",
          "action": "logout",
          "action-data": {},
        },
      ]
    else:
      %* [
        "To logout, just delete your login key from the data directory:",
        "",
        "rm " & storage.dataDir & "/login-key.png",
        "",
        "Then, rerun ansiwave and you will be logged out.",
        "",
        "Warning: if you don't keep a copy of the login key elsewhere,",
        "you will never be able to log back in!",
      ]

proc toHtml(node: JsonNode): string

proc toHtml(node: OrderedTable[string, JsonNode]): string =
  let nodeType = node["type"].str
  case nodeType:
  of "rect":
    result &= "<div title='Post'>"
    for child in node["children"]:
      result &= toHtml(child)
    if node.hasKey("action") and node.hasKey("action-accessible-text"):
      # TODO: make this link go somewhere
      result &= "<br/><a href=''>" & node["action-accessible-text"].str & "</a>"
    result &= "</div>"
  of "button":
    result &= "<button>" & node["text"].str & "</button>"
  of "editor":
    result &= "<div>Editor not supported in HTML version for now</div>"
  else:
    discard

proc toHtml(node: JsonNode): string =
  case node.kind:
  of JString:
    result = node.str.stripCodes & "\n"
  of JObject:
    result = toHtml(node.fields)
  of JArray:
    for item in node.elems:
      result &= toHtml(item)
  else:
    raise newException(Exception, "Unhandled JSON type")

proc toHtml*(comp: Component): string =
  var finishedLoading = false
  comp.toJson(finishedLoading).toHtml

proc render*(tb: var iw.TerminalBuffer, node: string, x: int, y: var int) =
  var runes = node.toRunes
  codes.deleteAfter(runes, editorWidth - 1)
  codes.write(tb, x, y, $runes)
  y += 1

proc render*(tb: var iw.TerminalBuffer, node: JsonNode, x: int, y: var int, focusIndex: int, areas: var seq[ViewFocusArea])

proc render*(tb: var iw.TerminalBuffer, node: OrderedTable[string, JsonNode], x: int, y: var int, focusIndex: int, areas: var seq[ViewFocusArea]) =
  let
    isFocused = focusIndex == areas.len
    yStart = y
    nodeType = node["type"].str
  var
    xStart = x
    xEnd = x + editorWidth + 1
  case nodeType:
  of "rect":
    y += 1
    for child in node["children"]:
      render(tb, child, x + 1, y, focusIndex, areas)
    iw.drawRect(tb, xStart, yStart, xEnd, y, doubleStyle = isFocused)
    if node.hasKey("children-after"):
      for child in node["children-after"]:
        var y = yStart + 1
        render(tb, child, x + 1, y, focusIndex, areas)
    if node.hasKey("top-right-focused") and isFocused:
      iw.write(tb, xEnd - node["top-right-focused"].str.runeLen, yStart, node["top-right-focused"].str)
    elif node.hasKey("top-right"):
      iw.write(tb, xEnd - node["top-right"].str.runeLen, yStart, node["top-right"].str)
    if node.hasKey("bottom-left-focused") and isFocused:
      iw.write(tb, x + 1, y, node["bottom-left-focused"].str)
    elif node.hasKey("bottom-left"):
      iw.write(tb, x + 1, y, node["bottom-left"].str)
    y += 1
  of "button":
    if node.hasKey("align") and node["align"].str == "left":
      xStart += 1
      xEnd = xStart + node["text"].str.len
      y += 1
      render(tb, node["text"].str, xStart, y)
      iw.drawRect(tb, xStart - 1, yStart, xEnd, y, doubleStyle = isFocused)
    else:
      xStart = max(x, editorWidth - node["text"].str.len + 1)
      y += 1
      render(tb, node["text"].str, xStart, y)
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
  of "editor":
    discard
  const focusables = ["rect", "button", "editor"].toHashSet
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

proc render*(tb: var iw.TerminalBuffer, node: JsonNode, x: int, y: var int, focusIndex: int, areas: var seq[ViewFocusArea]) =
  case node.kind:
  of JString:
    render(tb, node.str, x, y)
  of JObject:
    render(tb, node.fields, x, y, focusIndex, areas)
  of JArray:
    for item in node.elems:
      render(tb, item, x, y, focusIndex, areas)
  else:
    raise newException(Exception, "Unhandled JSON type")

