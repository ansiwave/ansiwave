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
from ./user import nil
from ./storage import nil
from wavecorepkg/paths import nil
from ./post import nil
from ./ui/simpleeditor import nil

type
  ComponentKind* = enum
    Post, User, Editor, Drafts, Sent, Login, Logout, Message, Search,
  Component* = ref object
    sig: string
    offset*: int
    case kind*: ComponentKind
    of Post:
      postContent: client.ChannelValue[client.Response]
      replies: client.ChannelValue[seq[entities.Post]]
    of User:
      showAllPosts*: bool
      tagsField*: simpleeditor.EditorSession
      tagsSig*: string
      editTagsRequest*: client.ChannelValue[client.Response]
      user*: client.ChannelValue[entities.User]
      userContent: client.ChannelValue[client.Response]
      userReplies: client.ChannelValue[seq[entities.Post]]
    of Editor:
      headers*: string
      session*: editor.EditorSession
      request*: client.ChannelValue[client.Response]
      requestBody*: string
      requestSig*: string
    of Message:
      message: string
    of Search:
      searchField*: simpleeditor.EditorSession
      searchTerm*: string
      searchKind*: entities.SearchKind
      searchResults*: client.ChannelValue[seq[entities.Post]]
      showResults*: bool
    of Drafts, Sent, Login, Logout:
      discard
  ViewFocusArea* = tuple[top: int, bottom: int, left: int, right: int, action: string, actionData: OrderedTable[string, JsonNode], copyableText: seq[string]]
  Draft = object
    target: string
    content: string
    sig: string
  Recent = object
    content: string
    sig: string

proc refresh*(clnt: client.Client, comp: Component) =
  case comp.kind:
  of Post:
    comp.postContent = client.query(clnt, paths.ansiwavez(paths.sysopPublicKey, comp.sig))
    comp.replies = client.queryPostChildren(clnt, paths.db(paths.sysopPublicKey), comp.sig, false, comp.offset)
  of User:
    comp.userContent = client.query(clnt, paths.ansiwavez(paths.sysopPublicKey, comp.sig))
    if comp.showAllPosts:
      comp.userReplies = client.queryUserPosts(clnt, paths.db(paths.sysopPublicKey), comp.sig, comp.offset)
    else:
      comp.userReplies = client.queryPostChildren(clnt, paths.db(paths.sysopPublicKey), comp.sig, true, comp.offset)
    if comp.sig != paths.sysopPublicKey:
      comp.user = client.queryUser(clnt, paths.db(paths.sysopPublicKey), comp.sig)
    comp.editTagsRequest.started = false
    comp.tagsSig = ""
  of Search:
    if comp.showResults:
      comp.searchResults = client.search(clnt, paths.db(paths.sysopPublicKey), comp.searchKind, comp.searchTerm, comp.offset)
  of Drafts, Sent, Editor, Login, Logout, Message:
    discard

proc initPost*(clnt: client.Client, sig: string): Component =
  result = Component(kind: Post, sig: sig)
  refresh(clnt, result)

proc initUser*(clnt: client.Client, key: string): Component =
  result = Component(kind: User, sig: key, tagsField: simpleeditor.init())
  refresh(clnt, result)

proc initEditor*(width: int, height: int, sig: string, headers: string): Component =
  result = Component(kind: Editor)
  result.headers = headers
  result.session = editor.init(editor.Options(bbsMode: true, sig: sig), width, height - navbar.height)

proc initDrafts*(clnt: client.Client): Component =
  result = Component(kind: Drafts)
  refresh(clnt, result)

proc initSent*(clnt: client.Client): Component =
  result = Component(kind: Sent)
  refresh(clnt, result)

proc initLogin*(): Component =
  Component(kind: Login)

proc initLogout*(): Component =
  Component(kind: Logout)

proc initMessage*(message: string): Component =
  Component(kind: Message, message: message)

proc initSearch*(): Component =
  Component(kind: Search, searchField: simpleeditor.init())

proc toJson*(entity: entities.Post, kind: string = "post"): JsonNode =
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
    lines = post.wrapLines(common.splitAfterHeaders(entity.content.value.uncompressed))
  %*{
    "type": "rect",
    "children": if lines.len > maxLines: lines[0 ..< maxLines] else: lines,
    "copyable-text": lines,
    "top-left": entity.tags,
    "top-right": (if kind == "post": replies else: ""),
    "bottom-left": if lines.len > maxLines: "see more" else: "",
    "action": "show-post",
    "action-data": {"type": kind, "sig": entity.content.sig},
    "action-accessible-text": replies,
  }

proc toJson*(posts: seq[entities.Post], offset: int, noResultsText: string, kind: string = "post"): JsonNode =
  result = JsonNode(kind: JArray)
  if offset > 0:
    result.add:
      %* {
        "type": "button",
        "text": "previous page",
        "action": "change-page",
        "action-data": {"offset-change": -entities.limit},
      }
  if posts.len > 0:
    for post in posts:
      result.elems.add(toJson(post, kind))
  else:
    result.elems.add(%noResultsText)
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
  let
    lines = post.wrapLines(strutils.splitLines(draft.content))
    isNew = strutils.endsWith(draft.sig, ".new")
    parts = strutils.split(draft.sig, '.')
    originalSig = parts[0]
  %*[
    {
      "type": "rect",
      "children": if lines.len > maxLines: lines[0 ..< maxLines] else: lines,
      "copyable-text": lines,
      "bottom-left": if lines.len > maxLines: "see more" else: "",
      "action": "show-editor",
      "action-data": {
        "sig": draft.sig,
        "headers": common.headers(user.pubKey, draft.target, if isNew: common.New else: common.Edit),
      },
    },
    {
      "type": "button",
      "text": if isNew: "see post that this is replying to" else: "see post that this is editing",
      "action": "show-post",
      "action-data": {"type": "post", "sig": originalSig},
    },
    "" # spacer
  ]

proc toJson*(recent: Recent): JsonNode =
  const maxLines = int(editorWidth / 4f)
  let lines = strutils.splitLines(recent.content)
  %* {
    "type": "rect",
    "children": if lines.len > maxLines: lines[0 ..< maxLines] else: lines,
    "copyable-text": lines,
    "bottom-left": if lines.len > maxLines: "see more" else: "",
    "action": "show-post",
    "action-data": {"type": "post", "sig": recent.sig},
  }

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
          let lines = strutils.splitLines(parsed.content)
          %*{
            "type": "rect",
            "children": post.wrapLines(lines),
            "copyable-text": lines,
          }
      ,
      if comp.postContent.ready and parsed.kind != post.Error:
        if parsed.key == user.pubKey:
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
              "sig": comp.sig & "." & parsed.sig & ".edit",
              "content": parsed.content,
              "headers": common.headers(user.pubKey, parsed.sig, common.Edit),
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
      if user.pubKey == "":
        %[]
      else:
        %* {
          "type": "button",
          "text": "write new post",
          "action": "show-editor",
          "action-data": {
            "sig": comp.sig & ".new",
            "headers": common.headers(user.pubKey, comp.sig, common.New),
          },
        }
      ,
      "", # spacer
      if not comp.replies.ready:
        %"loading posts"
      elif comp.replies.value.kind == client.Error:
        %"failed to load replies"
      else:
       toJson(comp.replies.value.valid, comp.offset, "no posts")
    ]
  of User:
    client.get(comp.userContent)
    client.get(comp.userReplies)
    finishedLoading =
      comp.userContent.ready and
      comp.userReplies.ready and
      (comp.sig == paths.sysopPublicKey or comp.user.ready)
    var parsed: post.Parsed
    %*[
      if comp.sig != paths.sysopPublicKey:
        client.get(comp.user)
        if not comp.user.ready or
            comp.user.value.kind == client.Error:
          %[]
        else:
          if comp.tagsSig != "":
            finishedLoading = false # so the editor will always refresh
            if comp.editTagsRequest.started:
              client.get(comp.editTagsRequest)
              if comp.editTagsRequest.ready:
                if comp.editTagsRequest.value.kind == client.Error:
                  %["error: " & comp.editTagsRequest.value.error, "refresh to continue"]
                else:
                  %["tags edited successfully (but they may take time to appear)", "refresh to continue"]
              else:
                %"editing tags..."
            else:
              simpleeditor.toJson(comp.tagsField, "press enter to edit tags or esc to cancel", "edit-tags")
          else:
            if comp.user.value.valid.tags.value == "":
              %[]
            else:
              % (" " & comp.user.value.valid.tags.value)
      else:
        %[]
      ,
      if not comp.userContent.ready:
        %"loading..."
      else:
        parsed = post.getFromLocalOrRemote(comp.userContent.value, comp.sig)
        if parsed.kind == post.Error:
          if comp.sig == user.pubKey:
            %"Your banner will be here. Put something about yourself...or not."
          else:
            %""
        else:
          let lines = post.wrapLines(strutils.splitLines(parsed.content))
          if comp.sig == user.pubKey and lines.len == 1 and lines[0] == "":
            %"Your banner will be here. Put something about yourself...or not."
          else:
            %*{
              "type": "rect",
              "children": lines,
              "copyable-text": lines,
            }
      ,
      if comp.userContent.ready and parsed.kind != post.Error:
        if parsed.key == user.pubKey:
          %* {
            "type": "button",
            "text": "edit banner",
            "action": "show-editor",
            "action-data": {
              "sig": comp.sig & "." & parsed.sig & ".edit",
              "content": parsed.content,
              "headers": common.headers(user.pubKey, parsed.sig, common.Edit),
            },
          }
        else:
          %[]
      elif comp.sig == user.pubKey:
        %* {
          "type": "button",
          "text": "create banner",
          "action": "show-editor",
          "action-data": {
            "sig": comp.sig & "." & comp.sig & ".edit",
            "headers": common.headers(user.pubKey, user.pubKey, common.Edit),
          },
        }
      else:
        %[]
      ,
      if comp.sig == user.pubKey:
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
            "headers": common.headers(user.pubKey, comp.sig, common.New),
          },
        }
      else:
        %[]
      ,
      if comp.sig == paths.sysopPublicKey:
        %[]
      else:
        %* {
          "type": "tabs",
          "text": ["journal posts", "all posts"],
          "index": (if comp.showAllPosts: 1 else: 0),
          "action": "toggle-user-posts",
          "action-data": {},
        }
      ,
      "", # spacer
      if not comp.userReplies.ready:
        %"loading posts"
      elif comp.userReplies.value.kind == client.Error:
        %"failed to load posts"
      else:
        toJson(comp.userReplies.value.valid, comp.offset, (if comp.showAllPosts: "no posts" else: "no journal posts"))
    ]
  of Editor:
    finishedLoading = true
    %*{
      "type": "editor",
      "action": "edit",
      "action-data": {},
    }
  of Drafts:
    finishedLoading = false # don't cache
    var json = JsonNode(kind: JArray)
    for filename in post.drafts():
      let newIdx = strutils.find(filename, ".new")
      if newIdx != -1:
        json.elems.add(toJson(Draft(content: storage.get(filename), target: filename[0 ..< newIdx], sig: filename)))
      else:
        let editIdx = strutils.find(filename, ".edit")
        if editIdx != -1:
          # filename is: original-sig.last-sig.edit
          let parts = strutils.split(filename, '.')
          if parts.len == 3:
            json.elems.add(toJson(Draft(content: storage.get(filename), target: parts[1], sig: filename)))
    json
  of Sent:
    finishedLoading = false # don't cache
    var json = %* [
      "These are your recently sent posts.",
      "They may take some time to appear on the board.",
      "",
    ]
    for filename in post.recents(user.pubKey):
      var parsed = post.Parsed(kind: post.Local)
      post.parseAnsiwave(storage.get(filename), parsed)
      if parsed.kind != post.Error:
        let parts = strutils.split(filename, '.')
        json.elems.add(toJson(Recent(content: parsed.content, sig: parts[0])))
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
            "action": "login",
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
        "", # spacer
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
  of Message:
    finishedLoading = false # don't cache
    % comp.message
  of Search:
    finishedLoading = false # so the editor will always refresh
    if comp.showResults:
      client.get(comp.searchResults)
    %* [
      simpleeditor.toJson(comp.searchField, "press enter to search", "search"),
      {
        "type": "tabs",
        "text": ["posts", "users", "tags"],
        "index": comp.searchKind.ord,
        "action": "change-search-type",
        "action-data": {},
      },
      "", # spacer
      if comp.showResults:
        if not comp.searchResults.ready:
          %"searching"
        elif comp.searchResults.value.kind == client.Error:
          %"failed to fetch search results"
        else:
          let kind =
            case comp.searchKind:
            of entities.Posts:
              "post"
            of entities.Users, entities.UserTags:
              "user"
          toJson(comp.searchResults.value.valid, comp.offset, "no results", kind)
      else:
        %""
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
  of Drafts:
    let pairs =
      {
        "type": "drafts",
        "board": board,
      }
    for pair in pairs:
      if pair[1].len > 0:
        fragments.add(pair[0] & ":" & pair[1])
  of Sent:
    let pairs =
      {
        "type": "sent",
        "board": board,
      }
    for pair in pairs:
      if pair[1].len > 0:
        fragments.add(pair[0] & ":" & pair[1])
  of Search:
    let pairs =
      {
        "type": "search",
        "board": board,
      }
    for pair in pairs:
      if pair[1].len > 0:
        fragments.add(pair[0] & ":" & pair[1])
  of Editor, Login, Logout, Message:
    discard
  strutils.join(fragments, ",")

proc render*(tb: var iw.TerminalBuffer, node: string, x: int, y: var int) =
  var runes = node.toRunes
  codes.deleteAfter(runes, editorWidth - 1)
  codes.write(tb, x, y, $runes)
  y += 1

var showPasteText*: bool

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
    if node.hasKey("top-left"):
      iw.write(tb, x + 1, yStart, node["top-left"].str)
    if node.hasKey("top-right"):
      iw.write(tb, xEnd - node["top-right"].str.runeLen, yStart, node["top-right"].str)
    if node.hasKey("bottom-left-focused") and isFocused:
      iw.write(tb, x + 1, y, node["bottom-left-focused"].str)
    elif node.hasKey("bottom-left"):
      iw.write(tb, x + 1, y, node["bottom-left"].str)
    if isFocused:
      let bottomRightText =
        if showPasteText:
          "now you can paste in the editor with ctrl l"
        else:
          "copy with ctrl k"
      iw.write(tb, xEnd - bottomRightText.runeLen, y, bottomRightText)
    y += 1
  of "button":
    xStart = max(x, editorWidth - node["text"].str.len + 1)
    y += 1
    render(tb, node["text"].str, xStart, y)
    iw.drawRect(tb, xStart - 1, yStart, xEnd, y, doubleStyle = isFocused)
    y += 1
  of "tabs":
    xStart += 1
    var
      tabX = 0
      tabIndex = 0
    for tab in node["text"]:
      codes.write(tb, xStart + tabX, y+1, tab.str)
      if tabIndex == node["index"].num:
        iw.drawRect(tb, xStart + tabX - 1, yStart, xStart + tabX + tab.str.runeLen, y+2, doubleStyle = isFocused)
      tabX += tab.str.runeLen + 2
      tabIndex += 1
    y += 3
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
  const focusables = ["rect", "button", "tabs", "editor"].toHashSet
  if nodeType in focusables:
    var area: ViewFocusArea
    area.top = yStart
    area.bottom = y
    area.left = xStart
    area.right = xEnd
    if node.hasKey("action"):
      area.action = node["action"].str
      area.actionData = node["action-data"].fields
    if node.hasKey("copyable-text"):
      for line in node["copyable-text"]:
        area.copyableText.add(line.str)
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

