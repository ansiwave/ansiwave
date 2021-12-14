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
from algorithm import nil

type
  ComponentKind* = enum
    Post, User, Editor, Drafts, Sent, Replies, Login, Logout, Message, Search,
  Component* = ref object
    board*: string
    sig: string
    offset*: int
    case kind*: ComponentKind
    of Post:
      postContent: client.ChannelValue[client.Response]
      replies: client.ChannelValue[seq[entities.Post]]
      post*: client.ChannelValue[entities.Post]
    of User:
      showAllPosts*: bool
      tagsField*: simpleeditor.EditorSession
      tagsSig*: string
      editTagsRequest*: client.ChannelValue[client.Response]
      user*: client.ChannelValue[entities.User]
      userContent: client.ChannelValue[client.Response]
      userPosts: client.ChannelValue[seq[entities.Post]]
    of Editor:
      headers*: string
      session*: editor.EditorSession
      request*: client.ChannelValue[client.Response]
      requestBody*: string
      requestSig*: string
    of Replies:
      userReplies: client.ChannelValue[seq[entities.Post]]
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
    time: int

proc refresh*(clnt: client.Client, comp: Component, board: string) =
  case comp.kind:
  of Post:
    comp.postContent = client.query(clnt, paths.ansiwavez(board, comp.sig))
    comp.replies = client.queryPostChildren(clnt, paths.db(board), comp.sig, false, comp.offset)
    comp.post = client.queryPost(clnt, paths.db(board), comp.sig, false)
  of User:
    comp.userContent = client.query(clnt, paths.ansiwavez(board, comp.sig))
    if comp.showAllPosts:
      comp.userPosts = client.queryUserPosts(clnt, paths.db(board), comp.sig, comp.offset)
    else:
      comp.userPosts = client.queryPostChildren(clnt, paths.db(board), comp.sig, true, comp.offset)
    if comp.sig != board:
      comp.user = client.queryUser(clnt, paths.db(board), comp.sig)
    comp.editTagsRequest.started = false
    comp.tagsSig = ""
  of Replies:
    comp.userReplies = client.queryUserReplies(clnt, paths.db(board), user.pubKey, comp.offset)
  of Search:
    if comp.showResults:
      comp.searchResults = client.search(clnt, paths.db(board), comp.searchKind, comp.searchTerm, comp.offset)
  of Drafts, Sent, Editor, Login, Logout, Message:
    discard

proc initPost*(clnt: client.Client, board: string, sig: string): Component =
  result = Component(kind: Post, board: board, sig: sig)
  refresh(clnt, result, board)

proc initUser*(clnt: client.Client, board: string, key: string): Component =
  result = Component(kind: User, board: board, sig: key, tagsField: simpleeditor.init())
  refresh(clnt, result, board)

proc initEditor*(width: int, height: int, board: string, sig: string, headers: string): Component =
  result = Component(kind: Editor, board: board)
  result.headers = headers
  result.session = editor.init(editor.Options(bbsMode: true, sig: sig), width, height - navbar.height)

proc initDrafts*(clnt: client.Client, board: string): Component =
  result = Component(kind: Drafts, board: board)
  refresh(clnt, result, board)

proc initSent*(clnt: client.Client, board: string): Component =
  result = Component(kind: Sent, board: board)
  refresh(clnt, result, board)

proc initReplies*(clnt: client.Client, board: string): Component =
  result = Component(kind: Replies, board: board)
  refresh(clnt, result, board)

proc initLogin*(): Component =
  Component(kind: Login)

proc initLogout*(): Component =
  Component(kind: Logout)

proc initMessage*(message: string): Component =
  Component(kind: Message, message: message)

proc initSearch*(board: string): Component =
  Component(kind: Search, board: board, searchField: simpleeditor.init())

proc createHash(pairs: seq[(string, string)]): string =
  var fragments: seq[string]
  for pair in pairs:
    if pair[1].len > 0:
      fragments.add(pair[0] & ":" & pair[1])
  strutils.join(fragments, ",")

proc toJson*(board: string, entity: entities.Post, kind: string = "post"): JsonNode =
  const maxLines = int(editorWidth / 4f)
  let
    replies =
      if entity.parent == board:
        if entity.reply_count == 1:
          "1 post"
        else:
          $entity.reply_count & " posts"
      else:
        if entity.reply_count == 1:
          "1 reply"
        else:
          $entity.reply_count & " replies"
    lines = common.splitAfterHeaders(entity.content.value.uncompressed)
    wrappedLines = post.wrapLines(lines)
    truncatedLines = if lines.len > maxLines: lines[0 ..< maxLines] else: lines
  %*{
    "type": "rect",
    "children": truncatedLines,
    "copyable-text": lines,
    "top-left": entity.tags,
    "top-right": (if kind == "post": replies else: ""),
    "bottom-left": if lines.len > maxLines: "see more" else: "",
    "action": "show-post",
    "action-data": {"type": kind, "sig": entity.content.sig},
    "accessible-text": replies,
    "accessible-hash": createHash(@{"type": kind, "id": entity.content.sig, "board": board}),
  }

proc toJson*(board: string, posts: seq[entities.Post], offset: int, noResultsText: string, kind: string = "post"): JsonNode =
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
      result.elems.add(toJson(board, post, kind))
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

proc toJson*(draft: Draft, board: string): JsonNode =
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
        "headers": common.headers(user.pubKey, draft.target, if isNew: common.New else: common.Edit, board),
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

proc toJson*(post: Recent): JsonNode =
  const maxLines = int(editorWidth / 4f)
  let lines = strutils.splitLines(post.content)
  %* {
    "type": "rect",
    "children": if lines.len > maxLines: lines[0 ..< maxLines] else: lines,
    "copyable-text": lines,
    "bottom-left": if lines.len > maxLines: "see more" else: "",
    "action": "show-post",
    "action-data": {"type": "post", "sig": post.sig},
  }

proc toJson*(posts: seq[Recent], offset: int): JsonNode =
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
      result.elems.add(toJson(post))
  else:
    result.elems.add(%"no posts")
  if posts.len == entities.limit:
    result.add:
      %* {
        "type": "button",
        "text": "next page",
        "action": "change-page",
        "action-data": {"offset-change": entities.limit},
      }

proc toJson*(comp: Component, finishedLoading: var bool): JsonNode =
  case comp.kind:
  of Post:
    client.get(comp.postContent)
    client.get(comp.replies)
    client.get(comp.post)
    finishedLoading = comp.postContent.ready and comp.replies.ready and comp.post.ready
    var parsed: post.Parsed
    %*[
      if not comp.postContent.ready:
        %"loading..."
      else:
        parsed = post.getFromLocalOrRemote(comp.postContent.value, comp.sig)
        if parsed.kind == post.Error:
          %"failed to load post"
        else:
          let
            lines = strutils.splitLines(parsed.content)
            wrappedLines = post.wrapLines(lines)
            animatedLines = post.animateLines(wrappedLines, comp.postContent.readyTime)
            tags =
              if comp.post.ready and comp.post.value.kind != client.Error:
                comp.post.value.valid.tags
              else:
                ""
          finishedLoading = finishedLoading and animatedLines == wrappedLines
          var json = %*{
            "type": "rect",
            "children": animatedLines,
            "copyable-text": lines,
            "top-left": tags,
          }
          if parsed.key != comp.board:
            json["accessible-text"] = %"see user"
            json["accessible-hash"] = %createHash(@{"type": "user", "id": parsed.key, "board": comp.board})
          json
      ,
      if comp.postContent.ready and parsed.kind != post.Error:
        if parsed.key == user.pubKey:
          %* {
            "type": "button",
            "text":
              if parsed.key == comp.board:
                "edit subboard"
              else:
                "edit post"
            ,
            "action": "show-editor",
            "action-data": {
              "sig": comp.sig & "." & parsed.sig & ".edit",
              "content": parsed.content,
              "headers": common.headers(user.pubKey, parsed.sig, common.Edit, comp.board),
            },
          }
        elif parsed.key != comp.board:
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
            "headers": common.headers(user.pubKey, comp.sig, common.New, comp.board),
          },
        }
      ,
      "", # spacer
      if not comp.replies.ready:
        %"loading posts"
      elif comp.replies.value.kind == client.Error:
        %"failed to load replies"
      else:
       toJson(comp.board, comp.replies.value.valid, comp.offset, "no posts")
    ]
  of User:
    client.get(comp.userContent)
    client.get(comp.userPosts)
    finishedLoading =
      comp.userContent.ready and
      comp.userPosts.ready and
      (comp.sig == comp.board or comp.user.ready)
    var parsed: post.Parsed
    %*[
      if comp.sig != comp.board:
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
          let lines = strutils.splitLines(parsed.content)
          if comp.sig == user.pubKey and lines.len == 1 and lines[0] == "":
            %"Your banner will be here. Put something about yourself...or not."
          else:
            let
              wrappedLines = post.wrapLines(lines)
              animatedLines = post.animateLines(wrappedLines, comp.userContent.readyTime)
            finishedLoading = finishedLoading and animatedLines == lines
            %*{
              "type": "rect",
              "children": animatedLines,
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
              "headers": common.headers(user.pubKey, parsed.sig, common.Edit, comp.board),
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
            "headers": common.headers(user.pubKey, user.pubKey, common.Edit, comp.board),
          },
        }
      else:
        %[]
      ,
      if comp.sig == user.pubKey:
        %* {
          "type": "button",
          "text":
            if comp.sig == comp.board:
              "create new subboard"
            else:
              "write new journal post"
          ,
          "action": "show-editor",
          "action-data": {
            "sig": comp.sig & ".new",
            "headers": common.headers(user.pubKey, comp.sig, common.New, comp.board),
          },
        }
      else:
        %[]
      ,
      if comp.sig == comp.board:
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
      if not comp.userPosts.ready:
        %"loading posts"
      elif comp.userPosts.value.kind == client.Error:
        %"failed to load posts"
      else:
        toJson(comp.board, comp.userPosts.value.valid, comp.offset, (if comp.sig == comp.board: "no subboards" elif comp.showAllPosts: "no posts" else: "no journal posts"))
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
        json.elems.add(toJson(Draft(content: storage.get(filename), target: filename[0 ..< newIdx], sig: filename), comp.board))
      else:
        let editIdx = strutils.find(filename, ".edit")
        if editIdx != -1:
          # filename is: original-sig.last-sig.edit
          let parts = strutils.split(filename, '.')
          if parts.len == 3:
            json.elems.add(toJson(Draft(content: storage.get(filename), target: parts[1], sig: filename), comp.board))
    json
  of Sent:
    finishedLoading = false # don't cache
    var recents: seq[Recent]
    for filename in post.recents(user.pubKey):
      var parsed = post.Parsed(kind: post.Local)
      post.parseAnsiwave(storage.get(filename), parsed)
      if parsed.kind != post.Error:
        let parts = strutils.split(filename, '.')
        recents.add(Recent(content: parsed.content, sig: parts[0], time: post.getTime(parsed)))
    recents = algorithm.sorted(recents,
      proc (x, y: Recent): int =
        if x.time < y.time: 1
        elif x.time > y.time: -1
        else: 0
    )
    recents = recents[comp.offset ..< min(comp.offset + entities.limit, recents.len)]
    %* [
      "These are your recently sent posts.",
      "They may take some time to appear on the board.",
      "",
      toJson(recents, comp.offset),
    ]
  of Replies:
    client.get(comp.userReplies)
    finishedLoading = false # don't cache
    %*[
      "These are replies to any of your posts.",
      "", # space
      if not comp.userReplies.ready:
        %"loading replies"
      elif comp.userReplies.value.kind == client.Error:
        %"failed to load replies"
      else:
        toJson(comp.board, comp.userReplies.value.valid, comp.offset, "no replies")
    ]
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
          toJson(comp.board, comp.searchResults.value.valid, comp.offset, "no results", kind)
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
    if "accessible-text" in node and "accessible-hash" in node:
      result &= "<br/><a href='#" & node["accessible-hash"].str & "'>" & node["accessible-text"].str & "</a>"
    result &= "</div>"
  else:
    discard

proc escapeHtml(s: string): string =
  strutils.multiReplace(s, ("&", "&amp;"), ("<", "&lt;"), (">", "&gt;"), ("\"", "&quot;"), ("'", "&apos;"))

proc toHtml(node: JsonNode): string =
  case node.kind:
  of JString:
    result = node.str.stripCodes.escapeHtml & "\n"
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
  let pairs =
    case comp.kind:
    of Post:
      @{
        "type": "post",
        "id": comp.sig,
        "board": board,
      }
    of User:
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
    of Drafts:
      @{
        "type": "drafts",
        "board": board,
      }
    of Sent:
      @{
        "type": "sent",
        "board": board,
      }
    of Replies:
      @{
        "type": "replies",
        "board": board,
      }
    of Search:
      @{
        "type": "search",
        "board": board,
      }
    of Editor, Login, Logout, Message:
      newSeq[(string, string)]()
  createHash(pairs)

proc render*(tb: var iw.TerminalBuffer, node: string, x: int, y: var int) =
  var runes = node.toRunes
  codes.deleteAfter(runes, editorWidth - 1)
  codes.writeMaybe(tb, x, y, $runes)
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
    if node.hasKey("top-left") and node["top-left"].str != "":
      let text = " " & node["top-left"].str & " "
      iw.write(tb, x + 1, yStart, text)
    if node.hasKey("top-right") and node["top-right"].str != "":
      let text = " " & node["top-right"].str & " "
      iw.write(tb, xEnd - text.runeLen, yStart, text)
    if isFocused and node.hasKey("bottom-left-focused") and node["bottom-left-focused"].str != "":
      let text = " " & node["bottom-left-focused"].str & " "
      iw.write(tb, x + 1, y, text)
    elif node.hasKey("bottom-left") and node["bottom-left"].str != "":
      let text = " " & node["bottom-left"].str & " "
      iw.write(tb, x + 1, y, text)
    if isFocused and node.hasKey("copyable-text"):
      let bottomRightText =
        if showPasteText:
          " now you can paste in the editor with ctrl " & (if iw.gIllwillInitialised: "l" else: "v") & " "
        else:
          " copy with ctrl " & (if iw.gIllwillInitialised: "k" else: "c") & " "
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
      codes.writeMaybe(tb, xStart + tabX, y+1, tab.str)
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

