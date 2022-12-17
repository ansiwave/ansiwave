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
from nimwave as nw import nil

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
  Button = ref object of nw.Node
    text: string
    align: string
    border: nw.Border
    action: string
    actionData: Table[string, JsonNode]
  Tabs = ref object of nw.Node
    action: string
    actionData: Table[string, JsonNode]
    text: seq[string]
    index: int
  EditorView = ref object of nw.Node
    action: string
    actionData: Table[string, JsonNode]

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

proc toNode*(entity: entities.Post, content: string, board: string, kind: string, sig: string): nw.Node =
  const maxLines = int(editorWidth / 4f)
  let
    replies = replyText(entity, board)
    lines = common.splitAfterHeaders(content)
    wrappedLines = post.wrapLines(lines)
    truncatedLines = if wrappedLines.len > maxLines: wrappedLines[0 ..< maxLines] else: wrappedLines
  context.Rect(
    children: nw.seq(truncatedLines),
    copyableText: lines,
    topLeft: if entity.parent == board: "" else: header(entity),
    topRight: (if kind == "post": replies else: ""),
    bottomRight: if wrappedLines.len > maxLines: "see more" else: "",
    action: "show-post",
    actionData: {"type": % kind, "sig": % sig}.toTable,
  )

proc toNode*(posts: seq[entities.Post], comp: Component, finishedLoading: var bool, noResultsText: string): seq[nw.Node] =
  if comp.offset > 0:
    result.add:
      Button(
        text: "previous page",
        align: "right",
        action: "change-page",
        actionData: {"offset-change": % -entities.limit}.toTable,
      )
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
        result.add(toNode(post, content, comp.board, kind, sig))
      else:
        finishedLoading = false
        showStillLoading = true
    if showStillLoading:
      result.add(nw.Text(str: "still loading"))
  else:
    result.add(nw.Text(str: noResultsText))
  if posts.len == entities.limit:
    result.add:
      Button(
        text: "next page",
        align: "right",
        action: "change-page",
        actionData: {"offset-change": % entities.limit}.toTable,
      )

proc toNode(content: string, readyTime: float, finishedLoading: var bool): seq[nw.Node] =
  let lines = strutils.splitLines(content)
  var
    sectionLines: seq[string]
    sectionTitle = ""
  proc flush(sectionLines: var seq[string], sectionTitle: var string, res: var seq[nw.Node], finishedLoading: var bool) =
    let
      wrappedLines = post.wrapLines(sectionLines)
      animatedLines = post.animateLines(wrappedLines, readyTime)
    finishedLoading = finishedLoading and animatedLines == wrappedLines
    if sectionLines.len > 0:
      res.add:
        context.Rect(
          children: nw.seq(animatedLines),
          copyableText: animatedLines,
          topLeft: truncate(sectionTitle, constants.editorWidth),
        )
      sectionLines = @[]
      sectionTitle = ""
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
        result.add:
          context.Rect(
            topLeft: truncate(text, constants.editorWidth - 2),
            children: nw.seq(truncate(url, constants.editorWidth)),
            copyableText: @[url],
            action: "go-to-url",
            actionData: {"url": % url}.toTable,
          )
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

proc toNode*(draft: Draft, board: string): seq[nw.Node] =
  const maxLines = int(editorWidth / 4f)
  let
    lines = post.wrapLines(strutils.splitLines(draft.content))
    isNew = strutils.endsWith(draft.sig, ".new")
    parts = strutils.split(draft.sig, '.')
    originalSig = parts[0]
  @[
    context.Rect(
      children: nw.seq(if lines.len > maxLines: lines[0 ..< maxLines] else: lines),
      copyableText: lines,
      bottomLeft: if lines.len > maxLines: "see more" else: "",
      action: "show-editor",
      actionData: {
        "sig": % draft.sig,
        "headers": % common.headers(user.pubKey, draft.target, if isNew: common.New else: common.Edit, board),
      }.toTable,
    ),
    Button(
      text: if isNew: "see post that this is replying to" else: "see post that this is editing",
      align: "right",
      action: "show-post",
      actionData: {"type": % "post", "sig": % originalSig}.toTable,
    ),
    nw.Text(str: "") # spacer
  ]

proc toNode*(recent: Recent): nw.Node =
  const maxLines = int(editorWidth / 4f)
  let lines = post.wrapLines(strutils.splitLines(recent.content))
  context.Rect(
    children: nw.seq(if lines.len > maxLines: lines[0 ..< maxLines] else: lines),
    copyableText: lines,
    bottomLeft: if lines.len > maxLines: "see more" else: "",
    action: "show-post",
    actionData: {"type": % "post", "sig": % recent.sig}.toTable,
  )

proc toNode*(posts: seq[Recent], offset: int): seq[nw.Node] =
  if offset > 0:
    result.add:
      Button(
        text: "previous page",
        align: "right",
        action: "change-page",
        actionData: {"offset-change": % -entities.limit}.toTable,
      )
  if posts.len > 0:
    for post in posts:
      result.add(toNode(post))
  else:
    result.add(nw.Text(str: "no posts"))
  if posts.len == entities.limit:
    result.add:
      Button(
        text: "next page",
        align: "right",
        action: "change-page",
        actionData: {"offset-change": % entities.limit}.toTable,
      )

proc toNodes*(comp: Component, finishedLoading: var bool): seq[nw.Node] =
  case comp.kind:
  of Post:
    client.get(comp.postContent)
    client.get(comp.replies)
    client.get(comp.post)
    finishedLoading = comp.postContent.ready and comp.replies.ready and comp.post.ready
    var parsed: post.Parsed
    nw.seq(
      if comp.sig != comp.board:
        if not comp.post.ready or
            comp.post.value.kind == client.Error:
          nw.seq()
        else:
          if comp.editExtraTags.sig != "":
            finishedLoading = false # so the editor will always refresh
            if comp.editExtraTags.request.started:
              client.get(comp.editExtraTags.request)
              if comp.editExtraTags.request.ready:
                if comp.editExtraTags.request.value.kind == client.Error:
                  nw.seq("error: " & comp.editExtraTags.request.value.error, "refresh to continue")
                else:
                  nw.seq("extra tags edited successfully (but they may take time to appear)", "refresh to continue")
              else:
                nw.seq("editing extra tags...")
            else:
              nw.seq(simpleeditor.SimpleEditor(
                id: "extra-tag-field",
                initialValue: comp.editExtraTags.initialValue,
                prompt: "press enter to edit extra tags or esc to cancel",
                action: "edit-extra-tags",
              ))
          else:
            if comp.post.value.valid.parent != comp.board:
              nw.seq(" " & header(comp.post.value.valid))
            else:
              nw.seq()
      else:
        nw.seq()
      ,
      if not comp.postContent.ready:
        nw.seq("loading...")
      else:
        parsed = post.getFromLocalOrRemote(comp.postContent.value, comp.sig)
        if parsed.kind == post.Error:
          nw.seq("failed to load post")
        else:
          toNode(parsed.content, comp.postContent.readyTime, finishedLoading)
      ,
      if comp.postContent.ready and parsed.kind != post.Error:
        if parsed.key == user.pubKey:
          nw.seq(Button(
            text:
              if parsed.key == comp.board:
                "edit subboard"
              else:
                "edit post"
            ,
            align: "right",
            action: "show-editor",
            actionData: {
              "sig": % (comp.sig & "." & parsed.sig & ".edit"),
              "content": % parsed.content,
              "headers": % common.headers(user.pubKey, parsed.sig, common.Edit, comp.board),
            }.toTable,
          ))
        elif parsed.key != comp.board:
          nw.seq(Button(
            text: "see user",
            align: "right",
            action: "show-post",
            actionData: {"type": % "user", "sig": % parsed.key}.toTable,
          ))
        else:
          nw.seq()
      else:
        nw.seq()
      ,
      if user.pubKey == "":
        nw.seq()
      else:
        nw.seq(Button(
          text: "write new post",
          align: "right",
          action: "show-editor",
          actionData: {
            "sig": % (comp.sig & ".new"),
            "headers": % common.headers(user.pubKey, comp.sig, common.New, comp.board),
          }.toTable,
        ))
      ,
      if comp.sig != comp.board:
        if comp.post.ready and comp.post.value.kind != client.Error:
          nw.seq(" " & replyText(comp.post.value.valid, comp.board))
        else:
          nw.seq()
      else:
        nw.seq()
      ,
      nw.seq(""), # spacer
      if not comp.replies.ready:
        nw.seq("loading posts")
      elif comp.replies.value.kind == client.Error:
        nw.seq("failed to load replies")
      else:
       toNode(comp.replies.value.valid, comp, finishedLoading, "")
    )
  of User:
    client.get(comp.userContent)
    client.get(comp.userPosts)
    finishedLoading =
      comp.userContent.ready and
      comp.userPosts.ready and
      (comp.sig == comp.board or comp.user.ready)
    var parsed: post.Parsed
    nw.seq(
      if comp.sig != comp.board:
        client.get(comp.user)
        if not comp.user.ready or
            comp.user.value.kind == client.Error:
          nw.seq()
        else:
          if comp.user.value.valid.user_id == 0:
            # if the user wasn't found, try checking in limbo
            if not comp.limbo:
              comp.limbo = true
              refresh(comp.client, comp, comp.board)
            nw.seq()
          else:
            if comp.editTags.sig != "":
              finishedLoading = false # so the editor will always refresh
              if comp.editTags.request.started:
                client.get(comp.editTags.request)
                if comp.editTags.request.ready:
                  if comp.editTags.request.value.kind == client.Error:
                    nw.seq("error: " & comp.editTags.request.value.error, "refresh to continue")
                  else:
                    nw.seq("tags edited successfully (but they may take time to appear)", "refresh to continue")
                else:
                  nw.seq("editing tags...")
              else:
                nw.seq(simpleeditor.SimpleEditor(
                  id: "tag-field",
                  initialValue: comp.editTags.initialValue,
                  prompt: "press enter to edit tags or esc to cancel",
                  action: "edit-tags",
                ))
            elif comp.limbo and comp.sig == user.pubKey:
              nw.seq("you're in \"limbo\"...a mod will add you to the board shortly.")
            else:
              nw.seq(" " & header(comp.user.value.valid))
      else:
        nw.seq()
      ,
      if not comp.userContent.ready:
        nw.seq("loading...")
      else:
        parsed = post.getFromLocalOrRemote(comp.userContent.value, comp.sig)
        if parsed.kind == post.Error:
          if comp.sig == user.pubKey:
            nw.seq("Your banner will be here. Put something about yourself...or not.")
          else:
            nw.seq()
        else:
          if comp.sig == user.pubKey and parsed.content == "":
            nw.seq("Your banner will be here. Put something about yourself...or not.")
          else:
            toNode(parsed.content, comp.userContent.readyTime, finishedLoading)
      ,
      if comp.userContent.ready and parsed.kind != post.Error:
        if parsed.key == user.pubKey:
          nw.seq(Button(
            text: "edit banner",
            align: "right",
            action: "show-editor",
            actionData: {
              "sig": % (comp.sig & "." & parsed.sig & ".edit"),
              "content": % parsed.content,
              "headers": % common.headers(user.pubKey, parsed.sig, common.Edit, comp.board),
            }.toTable,
          ))
        else:
          nw.seq()
      elif comp.sig == user.pubKey:
        nw.seq(Button(
          text: "create banner",
          align: "right",
          action: "show-editor",
          actionData: {
            "sig": % (comp.sig & "." & comp.sig & ".edit"),
            "headers": % common.headers(user.pubKey, user.pubKey, common.Edit, comp.board),
          }.toTable,
        ))
      else:
        nw.seq()
      ,
      if comp.sig == user.pubKey:
        nw.seq(Button(
          text:
            if comp.sig == comp.board:
              "create new subboard"
            else:
              "write new journal post"
          ,
          align: "right",
          action: "show-editor",
          actionData: {
            "sig": % (comp.sig & ".new"),
            "headers": % common.headers(user.pubKey, comp.sig, common.New, comp.board),
          }.toTable,
        ))
      else:
        nw.seq()
      ,
      if comp.sig == comp.board:
        nw.seq()
      else:
        nw.seq(Tabs(
          text: @["journal posts", "all posts"],
          index: (if comp.showAllPosts: 1 else: 0),
          action: "toggle-user-posts",
        ))
      ,
      nw.seq(""), # spacer
      if not comp.userPosts.ready:
        nw.seq("loading posts")
      elif comp.userPosts.value.kind == client.Error:
        nw.seq("failed to load posts")
      else:
        toNode(comp.userPosts.value.valid, comp, finishedLoading, (if comp.sig == comp.board: "no subboards" elif comp.showAllPosts: "no posts" else: "no journal posts"))
    )
  of Editor:
    finishedLoading = true
    nw.seq(EditorView(
      action: "edit",
    ))
  of Drafts:
    finishedLoading = false # don't cache
    var nodes: seq[nw.Node]
    for filename in post.drafts():
      let newIdx = strutils.find(filename, ".new")
      if newIdx != -1:
        nodes.add(toNode(Draft(content: storage.get(filename), target: filename[0 ..< newIdx], sig: filename), comp.board))
      else:
        let editIdx = strutils.find(filename, ".edit")
        if editIdx != -1:
          # filename is: original-sig.last-sig.edit
          let parts = strutils.split(filename, '.')
          if parts.len == 3:
            nodes.add(toNode(Draft(content: storage.get(filename), target: parts[1], sig: filename), comp.board))
    nodes
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
    nw.seq(
      "These are your recently sent posts.",
      "They may take some time to appear on the board.",
      "",
      toNode(recents, comp.offset),
    )
  of Replies:
    client.get(comp.userReplies)
    finishedLoading = false # don't cache
    nw.seq(
      "These are replies to any of your posts.",
      "", # space
      if not comp.userReplies.ready:
        nw.seq("loading replies")
      elif comp.userReplies.value.kind == client.Error:
        nw.seq("failed to load replies")
      else:
        toNode(comp.userReplies.value.valid, comp, finishedLoading, "no replies")
    )
  of Login:
    finishedLoading = true
    nw.seq(
      "",
      when defined(emscripten):
        nw.seq(
          "If you don't have an account, create one by saving your key.",
          "You will need this to login later so keep it somewhere safe:",
          Button(
            text: "save login key",
            align: "right",
            action: "create-user",
          ),
        )
      else:
        nw.seq(
          "If you don't have an account, create one here. This will generate",
          storage.dataDir & "/login-key.png which you can use to login anywhere in the future.",
          Button(
            text: "create account",
            align: "right",
            action: "create-user",
          ),
        )
      ,
      "",
      when defined(emscripten):
        nw.seq(
          "If you already have an account, add your key:",
          Button(
            text: "add existing login key",
            align: "right",
            action: "login",
          ),
        )
      else:
        nw.seq(
          "If you already have an account, copy your login key",
          "into the data directory:",
          "",
          "cp path/to/login-key.png " & storage.dataDir & "/.",
          "",
          "Then, rerun ansiwave and you will be logged in.",
        )
      ,
    )
  of Logout:
    finishedLoading = true
    when defined(emscripten):
      nw.seq(
        "",
        "Are you sure you want to logout?",
        "If you don't have a copy of your login key somewhere,",
        "you will never be able to login again!",
        Button(
          text: "cancel",
          align: "right",
          action: "go-back",
        ),
        "", # spacer
        Button(
          text: "continue logout",
          align: "right",
          action: "logout",
        ),
      )
    else:
      nw.seq(
        "To logout, just delete your login key from the data directory:",
        "",
        "rm " & storage.dataDir & "/login-key.png",
        "",
        "Then, rerun ansiwave and you will be logged out.",
        "",
        "Warning: if you don't keep a copy of the login key elsewhere,",
        "you will never be able to log back in!",
      )
  of Message:
    finishedLoading = false # don't cache
    nw.seq(comp.message)
  of Search:
    finishedLoading = false # so the editor will always refresh
    if comp.showResults:
      client.get(comp.searchResults)
    nw.seq(
      simpleeditor.SimpleEditor(
        id: "search-field",
        prompt: "press enter to search",
        action: "search",
      ),
      Tabs(
        text: @["posts", "users", "tags"],
        index: comp.searchKind.ord,
        action: "change-search-type",
      ),
      if comp.showResults:
        if not comp.searchResults.ready:
          nw.seq("searching")
        elif comp.searchResults.value.kind == client.Error:
          nw.seq("failed to fetch search results", comp.searchResults.value.error)
        else:
          toNode(comp.searchResults.value.valid, comp, finishedLoading, "no results")
      else:
        nw.seq()
    )
  of Limbo:
    client.get(comp.limboResults)
    finishedLoading = comp.limboResults.ready
    nw.seq(
      if not comp.limboResults.ready:
        nw.seq("searching limbo")
      elif comp.limboResults.value.kind == client.Error:
        nw.seq("failed to search limbo", comp.limboResults.value.error)
      else:
        toNode(comp.limboResults.value.valid, comp, finishedLoading, "no posts in limbo")
    )

proc toNode*(comp: Component, finishedLoading: var bool): nw.Node =
  nw.Box(
    direction: nw.Direction.Vertical,
    children: toNodes(comp, finishedLoading),
  )

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

method render*(node: Button, ctx: var context.Context) =
  let
    text = node.text
    buttonWidth = text.runeLen + 2
    parentWidth = iw.width(ctx.tb)
    x =
      if node.align == "right":
        parentWidth - buttonWidth
      else:
        0
  ctx = nw.slice(ctx, x, 0, buttonWidth, 3)
  let border =
    if node.border != nw.Border.None:
      node.border
    else:
      let currIndex = ctx.data.focusAreas[].len
      var area: context.ViewFocusArea
      area.tb = ctx.tb
      if node.action != "":
        area.action = node.action
        area.actionData = node.actionData
      ctx.data.focusAreas[].add(area)
      if currIndex == ctx.data.focusIndex:
        nw.Border.Double
      else:
        nw.Border.Single
  context.render(
    nw.Box(
      direction: nw.Direction.Horizontal,
      border: border,
      children: nw.seq(text),
    ),
    ctx
  )

var showPasteText*: bool

method render*(node: context.Rect, ctx: var context.Context) =
  var
    y = 1
    remainingHeight = iw.height(ctx.tb).int
    remainingChildren = node.children.len
  for child in node.children:
    let initialHeight = int(remainingHeight / remainingChildren)
    var childContext = nw.slice(ctx, 1, y, max(0, iw.width(ctx.tb) - 2), max(0, initialHeight - 2))
    context.render(child, childContext)
    let actualHeight = iw.height(childContext.tb)
    y += actualHeight
    remainingHeight -= actualHeight
    remainingChildren -= 1
  ctx = nw.slice(ctx, 0, 0, iw.width(ctx.tb), y+1)

  let focused =
    block:
      let currIndex = ctx.data.focusAreas[].len
      var area: context.ViewFocusArea
      area.tb = ctx.tb
      if node.action != "":
        area.action = node.action
        area.actionData = node.actionData
      for line in node.copyableText:
        area.copyableText.add(line)
      ctx.data.focusAreas[].add(area)
      currIndex == ctx.data.focusIndex

  iw.drawRect(ctx.tb, 0, 0, iw.width(ctx.tb)-1, iw.height(ctx.tb)-1, doubleStyle = focused)

  for child in node.childrenAfter:
    var childContext = nw.slice(ctx, 1, 1, iw.width(ctx.tb), iw.height(ctx.tb))
    context.render(child, childContext)

  if node.topLeft != "":
    let text = " " & node.topLeft & " "
    iw.write(ctx.tb, 1, 0, text)
  if node.topRight != "":
    let text = " " & node.topRight & " "
    iw.write(ctx.tb, iw.width(ctx.tb) - 1 - text.runeLen, 0, text)
  if focused and node.bottomLeftFocused != "":
    let text = " " & node.bottomLeftFocused & " "
    iw.write(ctx.tb, 1, iw.height(ctx.tb)-1, text)
  elif node.bottomLeft != "":
    let text = " " & node.bottomLeft & " "
    iw.write(ctx.tb, 1, iw.height(ctx.tb)-1, text)

  when not defined(emscripten):
    if focused and node.copyableText.len > 0:
      let bottomRightText =
        if showPasteText:
          " now you can paste in the editor with ctrl " & (if iw.gIllwaveInitialized: "l" else: "v") & " "
        else:
          " copy with ctrl " & (if iw.gIllwaveInitialized: "k" else: "c") & " "
      iw.write(ctx.tb, iw.width(ctx.tb) - 1 - bottomRightText.runeLen, iw.height(ctx.tb)-1, bottomRightText)

method render*(node: Tabs, ctx: var context.Context) =
  ctx = nw.slice(ctx, 0, 0, iw.width(ctx.tb), 3)
  let currIndex = ctx.data.focusAreas[].len
  var area: context.ViewFocusArea
  area.tb = ctx.tb
  if node.action != "":
    area.action = node.action
    area.actionData = node.actionData
  ctx.data.focusAreas[].add(area)
  let focused = currIndex == ctx.data.focusIndex
  var
    tabs: seq[nw.Node]
    tabIndex = 0
  for tab in node.text:
    let border =
      if tabIndex == node.index:
        if focused:
          nw.Border.Double
        else:
          nw.Border.Single
      else:
        nw.Border.Hidden
    tabs.add(Button(text: tab, border: border))
    tabIndex += 1
  context.render(
    nw.Box(
      direction: nw.Direction.Horizontal,
      children: tabs,
    ),
    ctx
  )

