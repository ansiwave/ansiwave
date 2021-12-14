from ./illwill as iw import `[]`, `[]=`
from wavecorepkg/db/vfs import nil
from wavecorepkg/db/entities import nil
from wavecorepkg/client import nil
from os import nil
from ./ui import Component
from ./ui/editor import nil
from ./ui/simpleeditor import nil
from ./ui/navbar import nil
from ./constants import nil
import pararules
from pararules/engine import Session, Vars
from json import JsonNode
import tables, sets
from ./user import nil
from ./storage import nil
from wavecorepkg/paths import nil
from wavecorepkg/common import nil
from wavecorepkg/wavescript import nil
from ./post import CommandTreesRef
from times import nil
from ./midi import nil
from ./sound import nil
from strutils import nil
from uri import nil

when defined(emscripten):
  from wavecorepkg/client/emscripten import nil

type
  Id* = enum
    Global,
  Attr* = enum
    Board, Client, Hash,
    SelectedPage, AllPages, PageBreadcrumbs, PageBreadcrumbsIndex,
    Signature, ComponentData, FocusIndex, ScrollY,
    View, ViewCommands, ViewHeight, ViewFocusAreas, MidiProgress,
    HasDrafts, HasSent,
  ViewFocusAreaSeq = seq[ui.ViewFocusArea]
  Page = tuple
    id: int
    sig: string
    data: Component
    focusIndex: int
    scrollY: int
    view: JsonNode
    viewCommands: CommandTreesRef
    viewHeight: int
    viewFocusAreas: ViewFocusAreaSeq
    midiProgress: MidiProgressType
  PageTable = ref Table[string, Page]
  StringSeq = seq[string]
  MidiProgressType = ref object
    midiResult: midi.PlayResult
    time: tuple[start: float, stop: float]
  ClientType = client.Client

schema Fact(Id, Attr):
  Board: string
  Client: ClientType
  Hash: string
  SelectedPage: string
  AllPages: PageTable
  PageBreadcrumbs: StringSeq
  PageBreadcrumbsIndex: int
  HasDrafts: bool
  HasSent: bool
  Signature: string
  ComponentData: Component
  FocusIndex: int
  ScrollY: int
  View: JsonNode
  ViewCommands: CommandTreesRef
  ViewHeight: int
  ViewFocusAreas: ViewFocusAreaSeq
  MidiProgress: MidiProgressType

type
  BbsSession* = Session[Fact, Vars[Fact]]

proc routeHash(session: var auto, clnt: client.Client, hash: string)

let rules =
  ruleset:
    rule getGlobals(Fact):
      what:
        (Global, Board, board)
        (Global, Hash, hash)
        (Global, SelectedPage, selectedPage)
        (Global, AllPages, pages)
        (Global, PageBreadcrumbs, breadcrumbs)
        (Global, PageBreadcrumbsIndex, breadcrumbsIndex)
        (Global, HasDrafts, hasDrafts)
        (Global, HasSent, hasSent)
    rule changeSelectedPage(Fact):
      what:
        (Global, PageBreadcrumbs, breadcrumbs)
        (Global, PageBreadcrumbsIndex, breadcrumbsIndex)
      then:
        session.insert(Global, SelectedPage, breadcrumbs[breadcrumbsIndex])
        session.insert(Global, HasDrafts, post.drafts().len > 0)
        session.insert(Global, HasSent, post.recents(user.pubKey).len > 0)
    rule updateHashWhenPageChanges(Fact):
      what:
        (Global, Board, board, then = false)
        (Global, Hash, hash, then = false)
        (Global, SelectedPage, selectedPage)
        (Global, AllPages, pages, then = false)
      then:
        if pages != nil and pages.hasKey(selectedPage):
          let
            page = pages[selectedPage]
            newHash = ui.toHash(page.data, board)
          if hash != newHash:
            when defined(emscripten):
              emscripten.setHash(newHash)
            session.insert(Global, Hash, newHash)
    rule updatePageWhenHashChanges(Fact):
      what:
        (Global, Board, board, then = false)
        (Global, Hash, hash)
        (Global, Client, client)
        (Global, SelectedPage, selectedPage, then = false)
        (Global, AllPages, pages, then = false)
      then:
        if pages != nil and pages.hasKey(selectedPage):
          let
            page = pages[selectedPage]
            pageHash = ui.toHash(page.data, board)
          if hash != pageHash:
            session.routeHash(client, hash)
    rule getPage(Fact):
      what:
        (id, Signature, sig)
        (id, ComponentData, data)
        (id, FocusIndex, focusIndex)
        (id, ScrollY, scrollY)
        (id, View, view)
        (id, ViewCommands, viewCommands)
        (id, ViewHeight, viewHeight)
        (id, ViewFocusAreas, viewFocusAreas)
        (id, MidiProgress, midiProgress)
      thenFinally:
        var t: PageTable
        new t
        for page in session.queryAll(this):
          t[page.sig] = page
        session.insert(Global, AllPages, t)

proc goToPage(session: var auto, sig: string) =
  let globals = session.query(rules.getGlobals)
  var
    breadcrumbs = globals.breadcrumbs
    idx = globals.breadcrumbsIndex

  # if there are breadcrumbs beyond the current page, remove them
  if globals.breadcrumbsIndex < breadcrumbs.len - 1:
    breadcrumbs = breadcrumbs[0 .. idx]

  # add the new breadcrumb if it doesn't already exist
  if breadcrumbs.len == 0 or breadcrumbs[breadcrumbs.len - 1] != sig:
    breadcrumbs.add(sig)
    idx += 1

  session.insert(Global, PageBreadcrumbs, breadcrumbs)
  session.insert(Global, PageBreadcrumbsIndex, idx)

var
  nextPageId = Id.high.ord + 1
  sigToPageId: Table[string, int]

proc insertPage(session: var auto, comp: ui.Component, sig: string) =
  let id =
    if sigToPageId.hasKey(sig):
      sigToPageId[sig]
    else:
      let n = nextPageId
      sigToPageId[sig] = n
      nextPageId += 1
      n

  session.insert(id, Signature, sig)
  session.insert(id, ComponentData, comp)
  session.insert(id, FocusIndex, 0)
  session.insert(id, ScrollY, 0)
  session.insert(id, View, cast[JsonNode](nil))
  session.insert(id, ViewCommands, cast[CommandTreesRef](nil))
  session.insert(id, ViewHeight, 0)
  session.insert(id, ViewFocusAreas, @[])
  session.insert(id, MidiProgress, cast[MidiProgressType](nil))
  session.goToPage(sig)

proc routeHash(session: var auto, clnt: client.Client, hash: Table[string, string]) =
  if "board" notin hash:
    session.insertPage(ui.initMessage("Can't navigate to this page"), "message")
    return
  session.insert(Global, Board, hash["board"])
  client.setReadUrl(clnt, paths.address & "/" & paths.boardsDir & "/" & hash["board"] & "/" & paths.gitDir & "/" & paths.dbDir & "/" & paths.dbFilename)
  if "type" in hash and "id" in hash:
    if sigToPageId.hasKey(hash["id"]):
      session.goToPage(hash["id"])
    else:
      if hash["type"] == "user":
        session.insertPage(ui.initUser(clnt, hash["board"], hash["id"]), hash["id"])
      else:
        session.insertPage(ui.initPost(clnt, hash["board"], hash["id"]), hash["id"])
  elif "type" in hash:
    case hash["type"]:
    of "drafts":
      session.insertPage(ui.initDrafts(clnt, hash["board"]), "drafts")
    of "sent":
      session.insertPage(ui.initSent(clnt, hash["board"]), "sent")
    of "replies":
      session.insertPage(ui.initReplies(clnt, hash["board"]), "replies")
    of "search":
      session.insertPage(ui.initSearch(hash["board"]), "search")
    else:
      discard
  elif "key" in hash and "algo" in hash:
    if user.pubKey == "":
      if user.createUser(hash["key"], hash["algo"]):
        session.insertPage(ui.initUser(clnt, hash["board"], user.pubKey), user.pubKey)
    else:
      session.insertPage(ui.initMessage("You must log out of your existing account before logging in to a new one."), "message")
  else:
    if hash["board"] in sigToPageId:
      session.goToPage(hash["board"])
    else:
      session.insertPage(ui.initUser(clnt, hash["board"], hash["board"]), hash["board"])

proc routeHash(session: var auto, clnt: client.Client, hash: string) =
  routeHash(session, clnt, editor.parseHash(hash))

proc insertHash*(session: var auto, hash: string) =
  session.insert(Global, Hash, hash)
  session.fireRules

proc initSession*(clnt: client.Client, hash: Table[string, string]): auto =
  result = initSession(Fact, autoFire = false)
  for r in rules.fields:
    result.add(r)
  result.insert(Global, Client, clnt)
  result.insert(Global, Hash, "")
  result.insert(Global, SelectedPage, "")
  result.insert(Global, AllPages, cast[PageTable](nil))
  let empty: StringSeq = @[]
  result.insert(Global, PageBreadcrumbs, empty)
  result.insert(Global, PageBreadcrumbsIndex, -1)
  result.insert(Global, HasDrafts, false)
  result.insert(Global, HasSent, false)
  result.routeHash(clnt, hash)
  result.fireRules

proc refresh(session: var auto, clnt: client.Client, page: Page) =
  session.insert(page.id, ScrollY, 0)
  session.insert(page.id, View, cast[JsonNode](nil))
  let globals = session.query(rules.getGlobals)
  ui.refresh(clnt, page.data, globals.board)

proc handleAction(session: var auto, clnt: client.Client, page: Page, width: int, height: int, input: tuple[key: iw.Key, codepoint: uint32], actionName: string, actionData: OrderedTable[string, JsonNode], focusIndex: var int): bool =
  case actionName:
  of "show-post":
    result = input.key in {iw.Key.Mouse, iw.Key.Enter}
    if result:
      let
        typ = actionData["type"].str
        sig = actionData["sig"].str
        globals = session.query(rules.getGlobals)
        comp =
          if typ == "user" or sig == user.pubKey:
            ui.initUser(clnt, globals.board, sig)
          else:
            ui.initPost(clnt, globals.board, sig)
      session.insertPage(comp, sig)
  of "change-page":
    result = input.key in {iw.Key.Mouse, iw.Key.Enter}
    if result:
      let change = actionData["offset-change"].num.int
      page.data.offset += change
      refresh(session, clnt, page)
  of "show-editor":
    result = input.key in {iw.Key.Mouse, iw.Key.Enter}
    if result:
      let
        sig = actionData["sig"].str
        headers = actionData["headers"].str
        globals = session.query(rules.getGlobals)
      # if the content is empty, we want to reinitialize the editor
      # so we start with the default content again
      if globals.pages.hasKey(sig) and not editor.isEmpty(globals.pages[sig].data.session):
        session.goToPage(sig)
      else:
        if storage.get(sig) == "" and actionData.hasKey("content"):
          discard storage.set(sig, actionData["content"].str)
        session.insertPage(ui.initEditor(width, height, globals.board, sig, headers), sig)
  of "toggle-user-posts":
    result = input.key in {iw.Key.Mouse, iw.Key.Enter, iw.Key.Left, iw.Key.Right}
    if result:
      page.data.showAllPosts = not page.data.showAllPosts
      page.data.offset = 0
      refresh(session, clnt, page)
  of "change-search-type":
    result = input.key in {iw.Key.Mouse, iw.Key.Enter, iw.Key.Left, iw.Key.Right}
    if result:
      let
        newIndex =
          if input.key == iw.Key.Left:
            page.data.searchKind.ord - 1
          else:
           page.data.searchKind.ord + 1
        newKind =
          if newIndex == -1:
            entities.SearchKind(page.data.searchKind.high.ord)
          elif newIndex > page.data.searchKind.high.ord:
            entities.SearchKind(0)
          else:
            entities.SearchKind(newIndex)
      page.data.searchKind = newKind
      page.data.offset = 0
      refresh(session, clnt, page)
  of "edit":
    if focusIndex == 0:
      if input.key == iw.Key.Up and editor.getCursorY(page.data.session) == 0:
        focusIndex -= 1
      else:
        result = input.key notin {iw.Key.Escape}
  of "search":
    result = input.key notin {iw.Key.Escape, iw.Key.Up, iw.Key.Down}
    if result:
      if input.key == iw.Key.Enter:
        page.data.searchTerm = simpleeditor.getContent(page.data.searchField)
        page.data.showResults = true
        page.data.offset = 0
        refresh(session, clnt, page)
      else:
        simpleeditor.onInput(page.data.searchField, input)
  of "edit-tags":
    result = input.key notin {iw.Key.Up, iw.Key.Down}
    if result:
      if input.key == iw.Key.Escape:
        page.data.tagsSig = ""
      elif input.key == iw.Key.Enter:
        let
          headers = common.headers(user.pubKey, page.data.tagsSig, common.Tags, page.data.board)
          (body, sig) = common.sign(user.keyPair, headers, simpleeditor.getContent(page.data.tagsField))
        page.data.editTagsRequest = client.submit(clnt, "ansiwave", body)
      else:
        simpleeditor.onInput(page.data.tagsField, input)
  of "go-back":
    result = input.key in {iw.Key.Mouse, iw.Key.Enter}
    if result:
      let globals = session.query(rules.getGlobals)
      if globals.breadcrumbsIndex > 0:
        session.insert(Global, PageBreadcrumbsIndex, globals.breadcrumbsIndex - 1)
  of "create-user":
    result = input.key in {iw.Key.Mouse, iw.Key.Enter}
    if result:
      user.createUser()
      let globals = session.query(rules.getGlobals)
      session.insert(Global, PageBreadcrumbsIndex, globals.breadcrumbsIndex - 1)
  of "login":
    when defined(emscripten):
      result = input.key in {iw.Key.Mouse, iw.Key.Enter}
      if result:
        var sess = session
        user.browsePrivateKey(proc () =
          let globals = sess.query(rules.getGlobals)
          if globals.breadcrumbsIndex > 0:
            sess.insert(Global, PageBreadcrumbsIndex, globals.breadcrumbsIndex - 1)
        )
  of "logout":
    result = input.key in {iw.Key.Mouse, iw.Key.Enter}
    if result:
      user.removeKey()
      let globals = session.query(rules.getGlobals)
      if globals.breadcrumbsIndex > 0:
        session.insert(Global, PageBreadcrumbsIndex, globals.breadcrumbsIndex - 1)
        session.fireRules
        refresh(session, clnt, page)
  else:
    discard

proc renderHtml*(session: auto): string =
  let
    globals = session.query(rules.getGlobals)
    page = globals.pages[globals.selectedPage]
  ui.toHtml(page.data)

proc isEditor(page: Page): bool =
  page.data.kind == ui.Editor

proc isEditor*(session: auto): bool =
  try:
    let
      globals = session.query(rules.getGlobals)
      page = globals.pages[globals.selectedPage]
    page.isEditor
  except Exception as ex:
    false

proc init*() =
  try:
    user.loadKey()
  except Exception as ex:
    echo ex.msg

  when defined(emscripten):
    midi.fetchSoundfont()

  # remove old cached files
  const deleteFromStorageSeconds = 60 * 60 * 24 # 1 day
  for filename in storage.list():
    if strutils.endsWith(filename, ".ansiwave"):
      var parsed = post.Parsed(kind: post.Local)
      post.parseAnsiwave(storage.get(filename), parsed)
      if parsed.kind != post.Error and times.toUnix(times.getTime()) - deleteFromStorageSeconds >= post.getTime(parsed):
        storage.remove(filename)

proc tick*(session: var auto, clnt: client.Client, width: int, height: int, input: tuple[key: iw.Key, codepoint: uint32], finishedLoading: var bool): iw.TerminalBuffer =
  session.fireRules
  let
    globals = session.query(rules.getGlobals)
    page = globals.pages[globals.selectedPage]
    maxScroll = max(1, int(height / 5))
    view =
      if page.view == nil:
        let v = ui.toJson(page.data, finishedLoading)
        if finishedLoading:
          session.insert(page.id, View, v)
          var cmds: CommandTreesRef
          new cmds
          for tree in post.linesToTrees(strutils.splitLines(ui.getContent(page.data))):
            case tree.kind:
            of wavescript.Valid:
              cmds[].add(tree)
            of wavescript.Error, wavescript.Discard:
              discard
          session.insert(page.id, ViewCommands, cmds)
        v
      else:
        finishedLoading = true
        page.view
    isPlaying =
      if page.isEditor:
        editor.isPlaying(page.data.session)
      else:
        page.midiProgress != nil

  var sess = session
  let
    backAction = proc () {.closure.} =
      if globals.breadcrumbsIndex > 0:
        sess.insert(Global, PageBreadcrumbsIndex, globals.breadcrumbsIndex - 1)

  # if there is any input, find the associated action
  var
    action: tuple[actionName: string, actionData: OrderedTable[string, JsonNode]]
    focusIndex = page.focusIndex
    scrollY = page.scrollY
  if (input.key != iw.Key.None or input.codepoint > 0):
    if input.key == iw.Key.Mouse:
      let info = iw.getMouse()
      if info.button == iw.MouseButton.mbLeft and info.action == iw.MouseButtonAction.mbaPressed:
        for i in 0 ..< page.viewFocusAreas.len:
          let area = page.viewFocusAreas[i]
          if info.x >= area.left and
              info.x <= area.right and
              info.y + scrollY >= area.top and
              info.y + scrollY <= area.bottom - 1 and
              info.y >= navbar.height:
            action = (area.action, area.actionData)
            focusIndex = i
            ui.showPasteText = false
            break
    elif focusIndex >= 0 and focusIndex < page.viewFocusAreas.len:
      let area = page.viewFocusAreas[focusIndex]
      action = (area.action, area.actionData)

  # handle the action
  if not handleAction(session, clnt, page, width, height, input, action.actionName, action.actionData, focusIndex):
    case input.key:
    of iw.Key.Up:
      if focusIndex == 0:
        if page.scrollY == 0:
          focusIndex = focusIndex - 1
      elif focusIndex > 0:
        focusIndex = focusIndex - 1
      ui.showPasteText = false
    of iw.Key.Down:
      if focusIndex < 0:
        focusIndex = 0
      elif page.viewFocusAreas.len > focusIndex + 1:
        focusIndex = focusIndex + 1
      ui.showPasteText = false
    of iw.Key.CtrlR:
      refresh(sess, clnt, page)
    of iw.Key.CtrlG:
      if page.data.kind == ui.User and page.data.user.ready and page.data.user.value.kind != client.Error:
        let tags = page.data.user.value.valid.tags
        refresh(sess, clnt, page)
        simpleeditor.setContent(page.data.tagsField, tags.value)
        page.data.tagsSig = tags.sig
    of iw.Key.CtrlK, iw.Key.CtrlC:
      if focusIndex >= 0 and focusIndex < page.viewFocusAreas.len:
        ui.showPasteText = true
        let area = page.viewFocusAreas[focusIndex]
        if area.copyableText.len > 0:
          editor.copyLines(area.copyableText)
    else:
      if not isPlaying and input.key == iw.Key.Escape:
        backAction()
        # since we have changed the page, we need to rerun this function from the beginning
        return tick(session, clnt, width, height, (iw.Key.None, 0'u32), finishedLoading)
    # adjust focusIndex and scrollY based on viewFocusAreas
    if focusIndex >= 0 and page.viewFocusAreas.len > 0:
      # don't let it go beyond the last focused area
      if focusIndex > page.viewFocusAreas.len - 1:
        focusIndex = page.viewFocusAreas.len - 1
      # when going up or down, if the next focus area's edge is
      # beyond the current viewable scroll area, adjust scrollY
      # so we can see it. if the adjustment is greater than maxScroll,
      # only scroll maxScroll rows and update the focusIndex.
      case input.key:
      of iw.Key.Up:
        if page.viewFocusAreas[focusIndex].top < page.scrollY + navbar.height:
          scrollY = page.viewFocusAreas[focusIndex].top - navbar.height
          let limit = page.scrollY - maxScroll
          if scrollY < limit:
            scrollY = limit
          if page.viewFocusAreas[focusIndex].bottom < scrollY:
            focusIndex += 1
      of iw.Key.Down:
        if page.viewFocusAreas[focusIndex].bottom > page.scrollY + height:
          scrollY = page.viewFocusAreas[focusIndex].bottom - height
          let limit = page.scrollY + maxScroll
          if scrollY > limit:
            scrollY = limit
          if page.viewFocusAreas[focusIndex].top > scrollY + height:
            focusIndex -= 1
      else:
        discard

  # render
  var
    y = - scrollY + navbar.height
    areas: seq[ui.ViewFocusArea]
  if page.isEditor:
    result = iw.newTerminalBuffer(width, height)
    let filteredInput =
      if page.focusIndex == 0:
        input
      elif input.key == iw.Key.Mouse:
        let info = iw.getMouse()
        if info.button == iw.MouseButton.mbLeft and
            info.action == iw.MouseButtonAction.mbaPressed and
            info.y >= navbar.height:
          focusIndex = 0
        input
      else:
        (iw.Key.None, 0'u32)
    editor.tick(page.data.session, result, 0, navbar.height, width, height - navbar.height, filteredInput, focusIndex == 0, finishedLoading)
    ui.render(result, view, 0, y, focusIndex, areas)
    var rightButtons: seq[(string, proc ())]
    var errorLines: seq[string]
    if page.data.request.chan != nil:
      client.get(page.data.request)
      if not page.data.request.ready:
        rightButtons.add((" sending... ", proc () {.closure.} = discard))
        finishedLoading = false # when a request is being sent, make sure the view refreshes
      elif page.data.request.value.kind == client.Valid:
        session.retract(page.id, ComponentData)
        storage.remove(page.sig)
        backAction()
        session.fireRules
        let
          idx = strutils.find(page.sig, ".edit")
          sig =
            # if it's an edit, go to the original sig
            if idx != -1:
              let parts = strutils.split(page.sig, '.')
              parts[0]
            # go to the new sig
            else:
              page.data.requestSig
        if storage.set(sig & ".ansiwave", page.data.requestBody):
          session.insertPage(if sig == user.pubKey: ui.initUser(clnt, globals.board, sig) else: ui.initPost(clnt, globals.board, sig), sig)
        return tick(session, clnt, width, height, (iw.Key.None, 0'u32), finishedLoading)
      else:
        let
          continueAction = proc () =
            page.data.request.chan = nil
            editor.setEditable(page.data.session, true)
          errorStr = page.data.request.value.error
        rightButtons.add((" continue editing ", continueAction))
        errorLines = @[
          "error (don't worry, a draft is saved)",
          if errorStr.len > constants.editorWidth:
            errorStr[0 ..< constants.editorWidth]
          else:
            errorStr
        ]
    else:
      let
        sendAction = proc () {.closure.} =
          editor.setEditable(page.data.session, false)
          let (body, sig) = common.sign(user.keyPair, page.data.headers, editor.getContent(page.data.session))
          page.data.requestBody = body
          page.data.requestSig = sig
          page.data.request = client.submit(clnt, "ansiwave", body)
      rightButtons.add((" send ", sendAction))
    if not isPlaying:
      var leftButtons: seq[(string, proc ())]
      when not defined(emscripten):
        leftButtons.add((" ← ", backAction))
      navbar.render(result, 0, 0, input, leftButtons, errorLines, rightButtons, focusIndex)
    page.data.session.fireRules
    editor.saveToStorage(page.data.session, page.sig)
  else:
    result = iw.newTerminalBuffer(width, when defined(emscripten): page.viewHeight else: height)
    ui.render(result, view, 0, y, focusIndex, areas)
    let
      upAction = proc () {.closure.} =
        if page.data.kind == ui.Post and
            page.data.post.ready and
            page.data.post.value.kind != client.Error:
          let sig = page.data.post.value.valid.parent
          if sig == page.data.post.value.valid.public_key:
            sess.insertPage(ui.initUser(clnt, globals.board, sig), sig)
          else:
            sess.insertPage(ui.initPost(clnt, globals.board, sig), sig)
      refreshAction = proc () {.closure.} =
        refresh(sess, clnt, page)
      searchAction = proc () {.closure.} =
        sess.insertPage(ui.initSearch(globals.board), "search")
    var leftButtons: seq[(string, proc ())]
    when not defined(emscripten):
      leftButtons &= @[(" ← ", backAction), (" ⟳ ", refreshAction)]
    if page.data.kind == ui.Post and finishedLoading:
      leftButtons &= @[(" ↑ ", upAction)]
    if page.sig != "search":
      leftButtons &= @[(" search ", searchAction)]
    when defined(emscripten):
      let content = ui.getContent(page.data)
      if content != "":
        let viewHtmlAction = proc () {.closure.} =
          emscripten.openNewTab(editor.initLink(content) & ",hash:" & paths.encode(globals.hash))
        leftButtons.add((" plain view ", viewHtmlAction))
    else:
      if iw.gIllwillInitialised:
        let copyLinkAction = proc () {.closure.} =
          editor.copyLink(paths.address & "#" & globals.hash)
          # redraw ui without double buffering so everything is visible again
          iw.setDoubleBuffering(false)
          var finishedLoading: bool
          discard tick(sess, clnt, width, height, (iw.Key.None, 0'u32), finishedLoading)
          iw.setDoubleBuffering(true)
        leftButtons.add((" copy link ", copyLinkAction))
    if page.midiProgress == nil:
      if page.viewCommands != nil and page.viewCommands[].len > 0:
        let
          playAction = proc () {.closure.} =
            try:
              if iw.gIllwillInitialised:
                discard post.compileAndPlayAll(page.viewCommands[])
              else:
                let midiResult = post.compileAndPlayAll(page.viewCommands[])
                let currTime = times.epochTime()
                var progress: MidiProgressType
                new progress
                progress.midiResult = midiResult
                progress.time = (currTime, currTime + midiResult.secs)
                sess.insert(page.id, MidiProgress, progress)
            except Exception as ex:
              discard
        leftButtons.add((" ♫ play ", playAction))
      var rightButtons: seq[(string, proc ())] =
        if page.sig == "login" or page.sig == "logout":
          @[]
        elif user.pubKey == "":
          let
            loginAction = proc () {.closure.} =
              sess.insertPage(ui.initLogin(), "login")
          @[(" login ", loginAction)]
        elif page.sig == user.pubKey:
          let
            logoutAction = proc () {.closure, gcsafe.} =
              {.cast(gcsafe).}:
                sess.insertPage(ui.initLogout(), "logout")
            downloadKeyAction = proc () {.closure.} =
              when defined(emscripten):
                user.downloadImage()
          when defined(emscripten):
            @[(" download login key ", downloadKeyAction), (" logout ", logoutAction)]
          else:
            @[(" logout ", logoutAction)]
        else:
          let
            draftsAction = proc () {.closure.} =
              sess.insertPage(ui.initDrafts(clnt, globals.board), "drafts")
            sentAction = proc () {.closure.} =
              sess.insertPage(ui.initSent(clnt, globals.board), "sent")
            repliesAction = proc () {.closure.} =
              sess.insertPage(ui.initReplies(clnt, globals.board), "replies")
            myPageAction = proc () {.closure.} =
              sess.insertPage(ui.initUser(clnt, globals.board, user.pubKey), user.pubKey)
          var s: seq[(string, proc ())]
          if globals.hasDrafts and page.sig != "drafts":
            s.add((" drafts ", draftsAction))
          if globals.hasSent and page.sig != "sent":
            s.add((" sent ", sentAction))
          if user.pubKey != "" and page.sig != "replies":
            s.add((" replies ", repliesAction))
          s.add((" my page ", myPageAction))
          s
      navbar.render(result, 0, 0, input, leftButtons, [], rightButtons, focusIndex)
    else:
      if page.midiProgress[].midiResult.playResult.kind == sound.Error:
        let
          continueAction = proc () =
            sess.insert(page.id, MidiProgress, cast[MidiProgressType](nil))
          errorStr = page.midiProgress[].midiResult.playResult.message
        var rightButtons: seq[(string, proc ())]
        rightButtons.add((" continue ", continueAction))
        let errorLines = @[
          "error",
          if errorStr.len > constants.editorWidth:
            errorStr[0 ..< constants.editorWidth]
          else:
            errorStr
        ]
        navbar.render(result, 0, 0, input, [], errorLines, rightButtons, focusIndex)
      else:
        let currTime = times.epochTime()
        if currTime > page.midiProgress[].time.stop or input.key in {iw.Key.Tab, iw.Key.Escape}:
          midi.stop(page.midiProgress[].midiResult.playResult.addrs)
          session.insert(page.id, MidiProgress, cast[MidiProgressType](nil))
        else:
          let progress = (currTime - page.midiProgress[].time.start) / (page.midiProgress[].time.stop - page.midiProgress[].time.start)
          iw.fill(result, 0, 0, constants.editorWidth + 1, 2, " ")
          iw.fill(result, 0, 0, int(progress * float(constants.editorWidth + 1)), 0, "▓")
          iw.write(result, 0, 1, "press tab to stop playing")

  # update values if necessary
  if focusIndex != page.focusIndex:
    session.insert(page.id, FocusIndex, focusIndex)
  if scrollY != page.scrollY:
    session.insert(page.id, ScrollY, scrollY)
  # we can't update view info after scrolling, or the y values will be incorrect
  if scrollY == 0 and (page.viewFocusAreas != areas or page.viewHeight != y):
    session.insert(page.id, ViewFocusAreas, areas)
    session.insert(page.id, ViewHeight, y)
    # if the view height has changed, emscripten needs to render again
    when defined(emscripten):
      if y != page.viewHeight:
        return tick(session, clnt, width, height, (iw.Key.None, 0'u32), finishedLoading)

proc getCurrentFocusArea*(session: var BbsSession): tuple[top: int, bottom: int] =
  session.fireRules
  let
    globals = session.query(rules.getGlobals)
    page = globals.pages[globals.selectedPage]
  if page.focusIndex >= 0 and page.focusIndex < page.viewFocusAreas.len:
    return (page.viewFocusAreas[page.focusIndex].top, page.viewFocusAreas[page.focusIndex].bottom)

proc main*(parsedUri: uri.Uri, origHash: Table[string, string]) =
  when not defined(emscripten):
    if uri.isAbsolute(parsedUri) and parsedUri.hostname != uri.parseUri(paths.address).hostname:
      var newUri = parsedUri
      newUri.anchor = ""
      let s = uri.`$`(newUri)
      paths.address = s
      paths.postAddress = s

  var hash = origHash
  if "board" notin origHash:
    hash["board"] = paths.defaultBoard

  vfs.register()
  var clnt = client.initClient(paths.address, paths.postAddress)
  client.start(clnt)

  init()

  # create session
  var session = initSession(clnt, hash)

  # start loop
  while true:
    var finishedLoading = false
    var tb = tick(session, clnt, iw.terminalWidth(), iw.terminalHeight(), (iw.getKey(), 0'u32), finishedLoading)
    # display and sleep
    iw.display(tb)
    os.sleep(constants.sleepMsecs)

