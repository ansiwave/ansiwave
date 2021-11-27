from ./illwill as iw import `[]`, `[]=`
import ./constants
import unicode
from ./codes import stripCodes
import json
import tables, sets
from wavecorepkg/db/entities import nil
from wavecorepkg/client import nil
from wavecorepkg/common import nil
from strutils import format
from os import `/`
from ./ui/editor import nil
from ./ui/navbar import nil
from ./crypto import nil
from ./storage import nil
from wavecorepkg/paths import nil
from ./post import nil

type
  ComponentKind* = enum
    Post, User, Editor, Drafts, Login, Logout,
  Component* = ref object
    sig: string
    offset*: int
    case kind*: ComponentKind
    of Post:
      postContent: client.ChannelValue[client.Response]
      replies: client.ChannelValue[seq[entities.Post]]
    of User:
      showAllPosts*: bool
      userContent: client.ChannelValue[client.Response]
      userReplies: client.ChannelValue[seq[entities.Post]]
    of Editor:
      headers*: string
      session*: editor.EditorSession
      request*: client.ChannelValue[client.Response]
      requestBody*: string
      requestSig*: string
    of Drafts, Login, Logout:
      discard
  ViewFocusArea* = tuple[top: int, bottom: int, left: int, right: int, action: string, actionData: OrderedTable[string, JsonNode]]
  Draft = object
    target: string
    content: string
    sig: string

proc refresh*(clnt: client.Client, comp: Component) =
  case comp.kind:
  of Post:
    comp.postContent = client.query(clnt, paths.ansiwavez(paths.sysopPublicKey, comp.sig))
    comp.replies = client.queryPostChildren(clnt, paths.db(paths.sysopPublicKey), comp.sig, comp.offset)
  of User:
    comp.userContent = client.query(clnt, paths.ansiwavez(paths.sysopPublicKey, comp.sig))
    if comp.showAllPosts:
      comp.userReplies = client.queryUserPosts(clnt, paths.db(paths.sysopPublicKey), comp.sig, comp.offset)
    else:
      comp.userReplies = client.queryPostChildren(clnt, paths.db(paths.sysopPublicKey), comp.sig, comp.offset)
  of Drafts, Editor, Login, Logout:
    discard

proc initPost*(clnt: client.Client, sig: string): Component =
  result = Component(kind: Post, sig: sig)
  refresh(clnt, result)

proc initUser*(clnt: client.Client, key: string): Component =
  result = Component(kind: User, sig: key)
  refresh(clnt, result)

proc initEditor*(width: int, height: int, sig: string, headers: string): Component =
  result = Component(kind: Editor)
  result.headers = headers
  result.session = editor.init(editor.Options(bbsMode: true, sig: sig), width, height - navbar.height)

proc initDrafts*(clnt: client.Client): Component =
  result = Component(kind: Drafts)
  refresh(clnt, result)

proc initLogin*(): Component =
  Component(kind: Login)

proc initLogout*(): Component =
  Component(kind: Logout)

proc toJson*(entity: entities.Post): JsonNode =
  const maxLines = int(editorWidth / 4f)
  let
    replies =
      if entity.parent == paths.sysopPublicKey:
        if entity.reply_count == 1:
          "1 post"
        else:
          $entity.reply_count & " posts"
      else:
        if entity.reply_count == 1:
          "1 reply"
        else:
          $entity.reply_count & " replies"
    lines = post.splitAfterHeaders(entity.content.value.uncompressed)
  %*{
    "type": "rect",
    "children": if lines.len > maxLines: lines[0 ..< maxLines] else: lines,
    "top-right": replies,
    "bottom-left": if lines.len > maxLines: "see more" else: "",
    "action": "show-post",
    "action-data": {"type": "post", "sig": entity.content.sig},
    "action-accessible-text": replies,
  }

proc toJson*(posts: seq[entities.Post], offset: int): JsonNode =
  result = JsonNode(kind: JArray)
  if offset > 0:
    result.add:
      %* {
        "type": "button",
        "text": "previous page",
        "action": "change-page",
        "action-data": {"offset-change": -entities.limit},
      }
  for post in posts:
    result.elems.add(toJson(post))
  if posts.len == entities.limit:
    result.add:
      %* {
        "type": "button",
        "text": "next page",
        "action": "change-page",
        "action-data": {"offset-change": entities.limit},
      }

proc toJson*(draft: Draft): JsonNode =
  const maxLines = int(editorWidth / 4f)
  let lines = strutils.splitLines(draft.content)
  %*[
    {
      "type": "rect",
      "children": if lines.len > maxLines: lines[0 ..< maxLines] else: lines,
      "bottom-left": if lines.len > maxLines: "see more" else: "",
      "action": "show-editor",
      "action-data": {
        "sig": draft.sig,
        "headers": common.headers(crypto.pubKey, draft.target, strutils.endsWith(draft.sig, ".new")),
      },
    },
    {
      "type": "button",
      "text": "context",
      "action": "show-post",
      "action-data": {"type": "post", "sig": draft.target},
    },
    "" # spacer
  ]

proc toJson*(comp: Component, finishedLoading: var bool): JsonNode =
  case comp.kind:
  of Post:
    client.get(comp.postContent)
    client.get(comp.replies)
    finishedLoading = comp.postContent.ready and comp.replies.ready
    var parsed: post.Parsed
    %*[
      if not comp.postContent.ready:
        %"loading..."
      else:
        parsed = post.getFromLocalOrRemote(comp.postContent.value, comp.sig)
        if parsed.kind == post.Error:
          %"failed to load post"
        else:
          %*{
            "type": "rect",
            "children": strutils.splitLines(parsed.content),
          }
      ,
      if parsed.kind != post.Error:
        if parsed.key == crypto.pubKey:
          %* {
            "type": "button",
            "text":
              if parsed.key == paths.sysopPublicKey:
                "edit subboard"
              else:
                "edit post"
            ,
            "action": "show-editor",
            "action-data": {
              "sig": comp.sig & ".edit",
              "content": parsed.content,
              "headers": common.headers(crypto.pubKey, parsed.sig, false),
            },
          }
        elif parsed.key != paths.sysopPublicKey:
          %* {
            "type": "button",
            "text": "see user",
            "action": "show-post",
            "action-data": {"type": "user", "sig": parsed.key},
          }
        else:
          %[]
      else:
        %[]
      ,
      if crypto.pubKey == "":
        %[]
      else:
        %* {
          "type": "button",
          "text": "write new post",
          "action": "show-editor",
          "action-data": {
            "sig": comp.sig & ".new",
            "headers": common.headers(crypto.pubKey, comp.sig, true),
          },
        }
      ,
      "", # spacer
      if not comp.replies.ready:
        %"loading posts"
      elif comp.replies.value.kind == client.Error:
        %"failed to load replies"
      else:
        if comp.replies.value.valid.len == 0:
          %"no posts"
        else:
          toJson(comp.replies.value.valid, comp.offset)
    ]
  of User:
    client.get(comp.userContent)
    client.get(comp.userReplies)
    finishedLoading = comp.userContent.ready and comp.userReplies.ready
    var parsed: post.Parsed
    %*[
      if not comp.userContent.ready:
        %"loading..."
      else:
        parsed = post.getFromLocalOrRemote(comp.userContent.value, comp.sig)
        if parsed.kind == post.Error:
          if comp.sig == crypto.pubKey:
            %"Your banner will be here. Put something about yourself...or not."
          else:
            %""
        else:
          let lines = strutils.splitLines(parsed.content)
          if comp.sig == crypto.pubKey and lines.len == 1 and lines[0] == "":
            %"Your banner will be here. Put something about yourself...or not."
          else:
            %*{
              "type": "rect",
              "children": lines,
            }
      ,
      if parsed.kind != post.Error:
        if parsed.key == crypto.pubKey:
          %* {
            "type": "button",
            "text": "edit banner",
            "action": "show-editor",
            "action-data": {
              "sig": comp.sig & ".edit",
              "content": parsed.content,
              "headers": common.headers(crypto.pubKey, parsed.sig, false),
            },
          }
        else:
          %[]
      elif comp.sig == crypto.pubKey:
        %* {
          "type": "button",
          "text": "create banner",
          "action": "show-editor",
          "action-data": {
            "sig": comp.sig & ".edit",
            "headers": common.headers(crypto.pubKey, "", true),
          },
        }
      else:
        %[]
      ,
      if comp.sig == crypto.pubKey:
        %* {
          "type": "button",
          "text":
            if comp.sig == paths.sysopPublicKey:
              "create new subboard"
            else:
              "write new journal post"
          ,
          "action": "show-editor",
          "action-data": {
            "sig": comp.sig & ".new",
            "headers": common.headers(crypto.pubKey, comp.sig, true),
          },
        }
      else:
        %[]
      ,
      if comp.sig == paths.sysopPublicKey:
        %[]
      else:
        %* {
          "type": "button",
          "text": (if comp.showAllPosts: "see only journal posts" else: "see all posts"),
          "action": "toggle-user-posts",
          "action-data": {
            "key": comp.sig,
          },
        }
      ,
      if not comp.userReplies.ready:
        %"loading posts"
      elif comp.userReplies.value.kind == client.Error:
        %"failed to load posts"
      else:
        if comp.userReplies.value.valid.len == 0:
          % (if comp.showAllPosts: "no posts" else: "no journal posts")
        else:
          toJson(comp.userReplies.value.valid, comp.offset)
    ]
  of Editor:
    finishedLoading = true
    %*{
      "type": "editor",
      "action": "edit",
      "action-data": {},
    }
  of Drafts:
    finishedLoading = true
    var json = JsonNode(kind: JArray)
    for filename in post.drafts():
      let newIdx = strutils.find(filename, ".new")
      if newIdx != -1:
        json.elems.add(toJson(Draft(content: storage.get(filename), target: filename[0 ..< newIdx], sig: filename)))
      else:
        let editIdx = strutils.find(filename, ".edit")
        if editIdx != -1:
          json.elems.add(toJson(Draft(content: storage.get(filename), target: filename[0 ..< editIdx], sig: filename)))
    json
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

proc getContent*(comp: Component): string =
  case comp.kind:
  of Post:
    if not comp.postContent.ready:
      ""
    else:
      let parsed = post.getFromLocalOrRemote(comp.postContent.value, comp.sig)
      if parsed.kind == post.Error:
        ""
      else:
        parsed.content
  of User:
    if not comp.userContent.ready:
      ""
    else:
      let parsed = post.getFromLocalOrRemote(comp.userContent.value, comp.sig)
      if parsed.kind == post.Error:
        ""
      else:
        parsed.content
  else:
    ""

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

proc toHash*(comp: Component, board: string): string =
  var fragments: seq[string]
  case comp.kind:
  of Post:
    let pairs = {
      "type": "post",
      "id": comp.sig,
      "board": board,
    }
    for pair in pairs:
      if pair[1].len > 0:
        fragments.add(pair[0] & ":" & pair[1])
  of User:
    let pairs =
      if comp.sig == board:
        @{
          "board": board,
        }
      else:
        @{
          "type": "user",
          "id": comp.sig,
          "board": board,
        }
    for pair in pairs:
      if pair[1].len > 0:
        fragments.add(pair[0] & ":" & pair[1])
  of Editor, Drafts, Login, Logout:
    discard
  strutils.join(fragments, ",")

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

