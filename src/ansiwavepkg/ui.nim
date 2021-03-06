from illwave as iw import `[]`, `[]=`, `==`
import ./constants
import unicode
from ansiutils/codes import stripCodes
import json
import tables
from wavecorepkg/db/entities import nil
from wavecorepkg/client import nil
from wavecorepkg/common import nil
from wavecorepkg/wavescript import nil
from strutils import format
from ./ui/editor import nil
from ./ui/navbar import nil
from ./ui/context import nil
from ./user import nil
from ./storage import nil
from wavecorepkg/paths import nil
from ./post import nil
from ./ui/simpleeditor import nil
from algorithm import nil
from chrono import nil
from urlly import nil
from nimwave import nil

type
  ComponentKind* = enum
    Post, User, Editor, Drafts, Sent, Replies, Login, Logout, Message, Search, Limbo,
  Component* = ref object
    client: client.Client
    board*: string
    sig: string
    offset*: int
    limbo*: bool
    cache: Table[string, client.ChannelValue[client.Response]]
    case kind*: ComponentKind
    of Post:
      postContent: client.ChannelValue[client.Response]
      replies: client.ChannelValue[seq[entities.Post]]
      post*: client.ChannelValue[entities.Post]
      editExtraTags*: TagState
    of User:
      showAllPosts*: bool
      user*: client.ChannelValue[entities.User]
      userContent: client.ChannelValue[client.Response]
      userPosts: client.ChannelValue[seq[entities.Post]]
      editTags*: TagState
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
      searchTerm*: string
      searchKind*: entities.SearchKind
      searchResults*: client.ChannelValue[seq[entities.Post]]
      showResults*: bool
    of Limbo:
      limboResults*: client.ChannelValue[seq[entities.Post]]
    of Drafts, Sent, Login, Logout:
      discard
  TagState = object
    initialValue*: string
    sig*: string
    request*: client.ChannelValue[client.Response]
  Draft = object
    target: string
    content: string
    sig: string
  Recent = object
    content: string
    sig: string
    time: int

proc refresh*(clnt: client.Client, comp: Component, board: string) =
  comp.cache = initTable[string, client.ChannelValue[client.Response]]()
  case comp.kind:
  of Post:
    comp.postContent = client.query(clnt, paths.ansiwave(board, comp.sig, isUrl = true, limbo = comp.limbo))
    comp.replies = client.queryPostChildren(clnt, paths.db(board, isUrl = true, limbo = comp.limbo), comp.sig, entities.Score, comp.offset)
    comp.post = client.queryPost(clnt, paths.db(board, isUrl = true, limbo = comp.limbo), comp.sig)
    comp.editExtraTags.request.started = false
    comp.editExtraTags.sig = ""
  of User:
    comp.userContent = client.query(clnt, paths.ansiwave(board, comp.sig, isUrl = true, limbo = comp.limbo))
    if comp.showAllPosts:
      comp.userPosts = client.queryUserPosts(clnt, paths.db(board, isUrl = true, limbo = comp.limbo), comp.sig, comp.offset)
    else:
      let sortBy =
        if comp.sig == board:
          entities.ReplyCount
        else:
          entities.Ts
      comp.userPosts = client.queryPostChildren(clnt, paths.db(board, isUrl = true, limbo = comp.limbo), comp.sig, sortBy, comp.offset)
    if comp.sig != board:
      comp.user = client.queryUser(clnt, paths.db(board, isUrl = true, limbo = comp.limbo), comp.sig)
    comp.editTags.request.started = false
    comp.editTags.sig = ""
  of Replies:
    comp.userReplies = client.queryUserReplies(clnt, paths.db(board, isUrl = true), user.pubKey, comp.offset)
  of Search:
    if comp.showResults:
      if comp.searchKind == entities.UserTags and comp.searchTerm == "modlimbo":
        comp.limbo = true
        comp.searchResults = client.search(clnt, paths.db(board, isUrl = true, limbo = true), comp.searchKind, comp.searchTerm, comp.offset)
      else:
        comp.limbo = false
        comp.searchResults = client.search(clnt, paths.db(board, isUrl = true), comp.searchKind, comp.searchTerm, comp.offset)
  of Limbo:
    comp.limboResults = client.search(clnt, paths.db(board, isUrl = true, limbo = true), entities.UserTags, "modlimbo", comp.offset)
  of Drafts, Sent, Editor, Login, Logout, Message:
    discard

proc initPost*(clnt: client.Client, board: string, sig: string, limbo: bool = false): Component =
  result = Component(kind: Post, client: clnt, board: board, sig: sig, limbo: limbo, editExtraTags: TagState())
  refresh(clnt, result, board)

proc initUser*(clnt: client.Client, board: string, key: string, limbo: bool = false): Component =
  result = Component(kind: User, client: clnt, board: board, sig: key, limbo: limbo, editTags: TagState())
  refresh(clnt, result, board)

proc initEditor*(width: int, height: int, board: string, sig: string, headers: string): Component =
  result = Component(kind: Editor, board: board)
  result.headers = headers
  result.session = editor.init(editor.Options(bbsMode: true, sig: sig), width, height - navbar.height)

proc initDrafts*(clnt: client.Client, board: string): Component =
  result = Component(kind: Drafts, client: clnt, board: board)
  refresh(clnt, result, board)

proc initSent*(clnt: client.Client, board: string): Component =
  result = Component(kind: Sent, client: clnt, board: board)
  refresh(clnt, result, board)

proc initReplies*(clnt: client.Client, board: string): Component =
  result = Component(kind: Replies, client: clnt, board: board)
  refresh(clnt, result, board)

proc initLogin*(): Component =
  Component(kind: Login)

proc initLogout*(): Component =
  Component(kind: Logout)

proc initMessage*(message: string): Component =
  Component(kind: Message, message: message)

proc initSearch*(clnt: client.Client, board: string): Component =
  Component(kind: Search, client: clnt, board: board)

proc initLimbo*(clnt: client.Client, board: string): Component =
  result = Component(kind: Limbo, client: clnt, board: board, limbo: true)
  refresh(clnt, result, board)

proc createHash(pairs: seq[(string, string)]): string =
  var fragments: seq[string]
  for pair in pairs:
    if pair[1].len > 0:
      fragments.add(pair[0] & ":" & pair[1])
  strutils.join(fragments, ",")

proc replyText(post: entities.Post, board: string): string =
  if post.parent == board:
    if post.reply_count == 1:
      "1 post"
    else:
      $post.reply_count & " posts"
  else:
    if post.reply_count == 1:
      "1 reply"
    else:
      $post.reply_count & " replies"

proc truncate(s: string, maxLen: int): string =
  if s.runeLen > maxLen:
    $s.toRunes[0 ..< maxLen]
  else:
    s

proc separate(parts: openArray[string]): string =
  for part in parts:
    if part != "":
      if result != "":
        result &= " "
      result &= part

proc header(entity: entities.Post): string =
  let
    tags = separate([entity.tags, entity.extra_tags.value])
    parts = [
      entity.display_name,
      if tags.len > 0:
        "[" & tags & "]"
      else:
        ""
      ,
      "on",
      chrono.format(chrono.Timestamp(entity.ts), "{year/4}-{month/2}-{day/2}"),
    ]
  separate(parts)

proc header(entity: entities.User): string =
  let
    tags = entity.tags.value
    parts = [
      entity.display_name,
      if tags.len > 0:
        "[" & tags & "]"
      else:
        ""
      ,
    ]
  separate(parts)

proc toJson*(entity: entities.Post, content: string, board: string, kind: string, sig: string): JsonNode =
  const maxLines = int(editorWidth / 4f)
  let
    replies = replyText(entity, board)
    lines = common.splitAfterHeaders(content)
    wrappedLines = post.wrapLines(lines)
    truncatedLines = if wrappedLines.len > maxLines: wrappedLines[0 ..< maxLines] else: wrappedLines
  %*{
    "type": "rect",
    "children": truncatedLines,
    "copyable-text": lines,
    "top-left": if entity.parent == board: "" else: header(entity),
    "top-right": (if kind == "post": replies else: ""),
    "bottom-left": if wrappedLines.len > maxLines: "see more" else: "",
    "action": "show-post",
    "action-data": {"type": kind, "sig": sig},
    "accessible-text": replies,
    "accessible-hash": createHash(@{"type": kind, "id": sig, "board": board}),
  }

proc toJson*(posts: seq[entities.Post], comp: Component, finishedLoading: var bool, noResultsText: string): JsonNode =
  result = JsonNode(kind: JArray)
  if comp.offset > 0:
    result.add:
      %* {
        "type": "button",
        "text": "previous page",
        "align": "right",
        "action": "change-page",
        "action-data": {"offset-change": -entities.limit},
      }
  var showStillLoading = false
  if posts.len > 0:
    for post in posts:
      let
        # this "post" is actually a user if there is no content sig
        # (this happens in the search results when "user" is selected)
        (kind, sig) =
          if post.content.sig == "":
            ("user", post.public_key)
          else:
            ("post", post.content.sig)
        (ready, content) =
          block:
            if sig notin comp.cache:
              comp.cache[sig] = client.query(comp.client, paths.ansiwave(comp.board, sig, isUrl = true, limbo = comp.limbo))
            client.get(comp.cache[sig])
            if comp.cache[sig].ready:
              (true, if comp.cache[sig].value.kind == client.Valid: comp.cache[sig].value.valid.body else: "")
            else:
              (false, "")
      if ready:
        result.elems.add(toJson(post, content, comp.board, kind, sig))
      else:
        finishedLoading = false
        showStillLoading = true
    if showStillLoading:
      result.elems.add(%"still loading")
  else:
    result.elems.add(%noResultsText)
  if posts.len == entities.limit:
    result.add:
      %* {
        "type": "button",
        "text": "next page",
        "align": "right",
        "action": "change-page",
        "action-data": {"offset-change": entities.limit},
      }

proc toJson(content: string, readyTime: float, finishedLoading: var bool): JsonNode =
  let lines = strutils.splitLines(content)
  var
    sectionLines: seq[string]
    sectionTitle = ""
  proc flush(sectionLines: var seq[string], sectionTitle: var string, res: JsonNode, finishedLoading: var bool) =
    let
      wrappedLines = post.wrapLines(sectionLines)
      animatedLines = post.animateLines(wrappedLines, readyTime)
    finishedLoading = finishedLoading and animatedLines == wrappedLines
    if sectionLines.len > 0:
      res.elems.add(%* {
        "type": "rect",
        "children": animatedLines,
        "copyable-text": animatedLines,
        "top-left": truncate(sectionTitle, constants.editorWidth),
      })
      sectionLines = @[]
      sectionTitle = ""
  result = %[]
  for i in 0 ..< lines.len:
    let strippedLine = codes.stripCodesIfCommand(lines[i])
    if strutils.startsWith(strippedLine, "/link "):
      var ctx = wavescript.initContext()
      let res = wavescript.parse(ctx, strippedLine)
      if res.kind == wavescript.Valid:
        flush(sectionLines, sectionTitle, result, finishedLoading)
        var
          url = ""
          parts = strutils.split(res.args[0].name, " ")
          words: seq[string]
        for part in parts:
          if urlly.parseUrl(part).scheme != "":
            url = part
          else:
            words.add(part)
        let text = strutils.join(words, " ")
        result.elems.add(%* {
          "type": "rect",
          "top-left": truncate(text, constants.editorWidth - 2),
          "children": [truncate(url, constants.editorWidth)],
          "copyable-text": [url],
          "action": "go-to-url",
          "action-data": {"url": url},
        })
      else:
        sectionLines.add(lines[i])
    elif strutils.startsWith(strippedLine, "/section ") or strippedLine == "/section":
      var ctx = wavescript.initContext()
      let res = wavescript.parse(ctx, strippedLine)
      if res.kind == wavescript.Valid:
        flush(sectionLines, sectionTitle, result, finishedLoading)
        sectionTitle = res.args[0].name
      else:
        sectionLines.add(lines[i])
    else:
      sectionLines.add(lines[i])
  flush(sectionLines, sectionTitle, result, finishedLoading)

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
      "align": "right",
      "action": "show-post",
      "action-data": {"type": "post", "sig": originalSig},
    },
    "" # spacer
  ]

proc toJson*(recent: Recent): JsonNode =
  const maxLines = int(editorWidth / 4f)
  let lines = post.wrapLines(strutils.splitLines(recent.content))
  %* {
    "type": "rect",
    "children": if lines.len > maxLines: lines[0 ..< maxLines] else: lines,
    "copyable-text": lines,
    "bottom-left": if lines.len > maxLines: "see more" else: "",
    "action": "show-post",
    "action-data": {"type": "post", "sig": recent.sig},
  }

proc toJson*(posts: seq[Recent], offset: int): JsonNode =
  result = JsonNode(kind: JArray)
  if offset > 0:
    result.add:
      %* {
        "type": "button",
        "text": "previous page",
        "align": "right",
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
        "align": "right",
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
      if comp.sig != comp.board:
        if not comp.post.ready or
            comp.post.value.kind == client.Error:
          %""
        else:
          if comp.editExtraTags.sig != "":
            finishedLoading = false # so the editor will always refresh
            if comp.editExtraTags.request.started:
              client.get(comp.editExtraTags.request)
              if comp.editExtraTags.request.ready:
                if comp.editExtraTags.request.value.kind == client.Error:
                  %["error: " & comp.editExtraTags.request.value.error, "refresh to continue"]
                else:
                  %["extra tags edited successfully (but they may take time to appear)", "refresh to continue"]
              else:
                %"editing extra tags..."
            else:
              %* {
                "type": "simple-editor",
                "id": "extra-tag-field",
                "initial-value": comp.editExtraTags.initialValue,
                "prompt": "press enter to edit extra tags or esc to cancel",
                "action": "edit-extra-tags",
              }
          else:
            if comp.post.value.valid.parent != comp.board:
              % (" " & header(comp.post.value.valid))
            else:
              %""
      else:
        %""
      ,
      if not comp.postContent.ready:
        %"loading..."
      else:
        parsed = post.getFromLocalOrRemote(comp.postContent.value, comp.sig)
        if parsed.kind == post.Error:
          %"failed to load post"
        else:
          toJson(parsed.content, comp.postContent.readyTime, finishedLoading)
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
            "align": "right",
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
            "align": "right",
            "action": "show-post",
            "action-data": {"type": "user", "sig": parsed.key},
            "accessible-text": "see user",
            "accessible-hash": createHash(@{"type": "user", "id": parsed.key, "board": comp.board}),
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
          "align": "right",
          "action": "show-editor",
          "action-data": {
            "sig": comp.sig & ".new",
            "headers": common.headers(user.pubKey, comp.sig, common.New, comp.board),
          },
        }
      ,
      if comp.sig != comp.board:
        if comp.post.ready and comp.post.value.kind != client.Error:
          % (" " & replyText(comp.post.value.valid, comp.board))
        else:
          %""
      else:
        %""
      ,
      "", # spacer
      if not comp.replies.ready:
        %"loading posts"
      elif comp.replies.value.kind == client.Error:
        %"failed to load replies"
      else:
       toJson(comp.replies.value.valid, comp, finishedLoading, "")
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
          if comp.user.value.valid.user_id == 0:
            # if the user wasn't found, try checking in limbo
            if not comp.limbo:
              comp.limbo = true
              refresh(comp.client, comp, comp.board)
            %[]
          else:
            if comp.editTags.sig != "":
              finishedLoading = false # so the editor will always refresh
              if comp.editTags.request.started:
                client.get(comp.editTags.request)
                if comp.editTags.request.ready:
                  if comp.editTags.request.value.kind == client.Error:
                    %["error: " & comp.editTags.request.value.error, "refresh to continue"]
                  else:
                    %["tags edited successfully (but they may take time to appear)", "refresh to continue"]
                else:
                  %"editing tags..."
              else:
                %* {
                  "type": "simple-editor",
                  "id": "tag-field",
                  "initial-value": comp.editTags.initialValue,
                  "prompt": "press enter to edit tags or esc to cancel",
                  "action": "edit-tags",
                }
            elif comp.limbo and comp.sig == user.pubKey:
              % "you're in \"limbo\"...a mod will add you to the board shortly."
            else:
              % (" " & header(comp.user.value.valid))
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
          if comp.sig == user.pubKey and parsed.content == "":
            %"Your banner will be here. Put something about yourself...or not."
          else:
            toJson(parsed.content, comp.userContent.readyTime, finishedLoading)
      ,
      if comp.userContent.ready and parsed.kind != post.Error:
        if parsed.key == user.pubKey:
          %* {
            "type": "button",
            "text": "edit banner",
            "align": "right",
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
          "align": "right",
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
          "align": "right",
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
        toJson(comp.userPosts.value.valid, comp, finishedLoading, (if comp.sig == comp.board: "no subboards" elif comp.showAllPosts: "no posts" else: "no journal posts"))
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
        toJson(comp.userReplies.value.valid, comp, finishedLoading, "no replies")
    ]
  of Login:
    finishedLoading = true
    %*[
      "",
      when defined(emscripten):
        %* [
          "If you don't have an account, create one by saving your key.",
          "You will need this to login later so keep it somewhere safe:",
          {
            "type": "button",
            "text": "save login key",
            "align": "right",
            "action": "create-user",
            "action-data": {},
          },
        ]
      else:
        %* [
          "If you don't have an account, create one here. This will generate",
          storage.dataDir & "/login-key.png which you can use to login anywhere in the future.",
          {
            "type": "button",
            "text": "create account",
            "align": "right",
            "action": "create-user",
            "action-data": {},
          },
        ]
      ,
      "",
      when defined(emscripten):
        %* [
          "If you already have an account, add your key:",
          {
            "type": "button",
            "text": "add existing login key",
            "align": "right",
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
          "align": "right",
          "action": "go-back",
          "action-data": {},
        },
        "", # spacer
        {
          "type": "button",
          "text": "continue logout",
          "align": "right",
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
    %* [comp.message]
  of Search:
    finishedLoading = false # so the editor will always refresh
    if comp.showResults:
      client.get(comp.searchResults)
    %* [
      {
        "type": "simple-editor",
        "id": "search-field",
        "prompt": "press enter to search",
        "action": "search",
      },
      {
        "type": "tabs",
        "text": ["posts", "users", "tags"],
        "index": comp.searchKind.ord,
        "action": "change-search-type",
        "action-data": {},
      },
      if comp.showResults:
        if not comp.searchResults.ready:
          %"searching"
        elif comp.searchResults.value.kind == client.Error:
          %["failed to fetch search results", comp.searchResults.value.error]
        else:
          toJson(comp.searchResults.value.valid, comp, finishedLoading, "no results")
      else:
        %""
    ]
  of Limbo:
    client.get(comp.limboResults)
    finishedLoading = comp.limboResults.ready
    %* [
      if not comp.limboResults.ready:
        %"searching limbo"
      elif comp.limboResults.value.kind == client.Error:
        %["failed to search limbo", comp.limboResults.value.error]
      else:
        toJson(comp.limboResults.value.valid, comp, finishedLoading, "no posts in limbo")
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
    of Limbo:
      @{
        "type": "limbo",
        "board": board,
      }
    of Editor, Login, Logout, Message:
      newSeq[(string, string)]()
  createHash(pairs)

proc buttonView(ctx: var context.Context, node: JsonNode) =
  let
    text = node["text"].str
    buttonWidth = text.runeLen + 2
    parentWidth = iw.width(ctx.tb)
    x =
      if "align" in node and node["align"].str == "right":
        parentWidth - buttonWidth
      else:
        0
  ctx = nimwave.slice(ctx, x, 0, buttonWidth, 3)
  let border =
    if "border" in node:
      node["border"].str
    else:
      let currIndex = ctx.data.focusAreas[].len
      var area: context.ViewFocusArea
      area.tb = ctx.tb
      if node.hasKey("action"):
        area.action = node["action"].str
        area.actionData = node["action-data"].fields
      ctx.data.focusAreas[].add(area)
      if currIndex == ctx.data.focusIndex:
        "double"
      else:
        "single"
  nimwave.render(ctx, %* {"type": "nimwave.hbox", "border": border, "children": [text]})

var showPasteText*: bool

proc rectView(ctx: var context.Context, node: JsonNode) =
  let children = if "children" in node: node["children"].elems else: @[]
  var
    y = 1
    remainingHeight = iw.height(ctx.tb).int
    remainingChildren = children.len
  for child in children:
    let initialHeight = int(remainingHeight / remainingChildren)
    var childContext = nimwave.slice(ctx, 1, y, max(0, iw.width(ctx.tb) - 2), max(0, initialHeight - 2))
    nimwave.render(childContext, child)
    let actualHeight = iw.height(childContext.tb)
    y += actualHeight
    remainingHeight -= actualHeight
    remainingChildren -= 1
  ctx = nimwave.slice(ctx, 0, 0, iw.width(ctx.tb), y+1)

  let focused =
    if "focused" in node:
      node["focused"].bval
    else:
      let currIndex = ctx.data.focusAreas[].len
      var area: context.ViewFocusArea
      area.tb = ctx.tb
      if node.hasKey("action"):
        area.action = node["action"].str
        area.actionData = node["action-data"].fields
      if "copyable-text" in node:
        for line in node["copyable-text"]:
          area.copyableText.add(line.str)
      ctx.data.focusAreas[].add(area)
      currIndex == ctx.data.focusIndex

  iw.drawRect(ctx.tb, 0, 0, iw.width(ctx.tb)-1, iw.height(ctx.tb)-1, doubleStyle = focused)

  if "children-after" in node:
    for child in node["children-after"]:
      var childContext = nimwave.slice(ctx, 1, 1, iw.width(ctx.tb), iw.height(ctx.tb))
      nimwave.render(childContext, child)

  if "top-left" in node and node["top-left"].str != "":
    let text = " " & node["top-left"].str & " "
    iw.write(ctx.tb, 1, 0, text)
  if "top-right" in node and node["top-right"].str != "":
    let text = " " & node["top-right"].str & " "
    iw.write(ctx.tb, iw.width(ctx.tb) - 1 - text.runeLen, 0, text)
  if focused and "bottom-left-focused" in node and node["bottom-left-focused"].str != "":
    let text = " " & node["bottom-left-focused"].str & " "
    iw.write(ctx.tb, 1, iw.height(ctx.tb)-1, text)
  elif "bottom-left" in node and node["bottom-left"].str != "":
    let text = " " & node["bottom-left"].str & " "
    iw.write(ctx.tb, 1, iw.height(ctx.tb)-1, text)

  when not defined(emscripten):
    if focused and "copyable-text" in node:
      let bottomRightText =
        if showPasteText:
          " now you can paste in the editor with ctrl " & (if iw.gIllwaveInitialized: "l" else: "v") & " "
        else:
          " copy with ctrl " & (if iw.gIllwaveInitialized: "k" else: "c") & " "
      iw.write(ctx.tb, iw.width(ctx.tb) - 1 - bottomRightText.runeLen, iw.height(ctx.tb)-1, bottomRightText)

proc tabsView(ctx: var context.Context, node: JsonNode) =
  ctx = nimwave.slice(ctx, 0, 0, iw.width(ctx.tb), 3)
  let currIndex = ctx.data.focusAreas[].len
  var area: context.ViewFocusArea
  area.tb = ctx.tb
  if node.hasKey("action"):
    area.action = node["action"].str
    area.actionData = node["action-data"].fields
  ctx.data.focusAreas[].add(area)
  let focused = currIndex == ctx.data.focusIndex
  var
    tabs = newJArray()
    tabIndex = 0
  for tab in node["text"]:
    let border =
      if tabIndex == node["index"].num:
        if focused:
          "double"
        else:
          "single"
      else:
        "none"
    tabs.add(%* {"type": "button", "text": tab.str, "border": border})
    tabIndex += 1
  nimwave.render(ctx, %* {"type": "nimwave.hbox", "children": tabs})

proc addComponents*(ctx: var context.Context) =
  ctx.components["button"] = buttonView
  ctx.components["rect"] = rectView
  ctx.components["tabs"] = tabsView
  ctx.components["cursor"] = simpleeditor.cursorView
  ctx.statefulComponents["simple-editor"] = simpleeditor.simpleEditorView

