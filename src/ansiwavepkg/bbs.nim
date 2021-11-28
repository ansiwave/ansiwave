from ./illwill as iw import `[]`, `[]=`
from wavecorepkg/db/vfs import nil
from wavecorepkg/client import nil
from os import nil
from ./ui import nil
from ./ui/editor import nil
from ./ui/navbar import nil
from ./constants import nil
import pararules
from pararules/engine import Session, Vars
from json import JsonNode
import tables, sets
from ./crypto import nil
from ./storage import nil
from wavecorepkg/paths import nil
from wavecorepkg/common import nil
from ./post import CommandTreesRef
from times import nil
from ./midi import nil
from strutils import nil

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
    Drafts,
  Component = ui.Component
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
  Drafts: bool
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
        (Global, Drafts, drafts)
    rule changeSelectedPage(Fact):
      what:
        (Global, PageBreadcrumbs, breadcrumbs)
        (Global, PageBreadcrumbsIndex, breadcrumbsIndex)
      then:
        session.insert(Global, SelectedPage, breadcrumbs[breadcrumbsIndex])
        session.insert(Global, Drafts, post.drafts().len > 0)
    rule updateHashWhenPageChanges(Fact):
      what:
        (Global, Board, board)
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
        (Global, Board, board)
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

proc routeHash(session: var auto, clnt: client.Client, hash: string) =
  let parts = editor.parseHash(hash)
  if parts.hasKey("board"):
    if parts.hasKey("type") and parts.hasKey("id"):
      if sigToPageId.hasKey(parts["id"]):
        session.goToPage(parts["id"])
      else:
        if parts["type"] == "user":
          session.insertPage(ui.initUser(clnt, parts["id"]), parts["id"])
        else:
          session.insertPage(ui.initPost(clnt, parts["id"]), parts["id"])
    else:
      if sigToPageId.hasKey(parts["board"]):
        session.goToPage(parts["board"])
      else:
        session.insertPage(ui.initUser(clnt, parts["board"]), parts["board"])
  elif parts.hasKey("key") and parts.hasKey("algo"):
    if crypto.pubKey == "":
      if crypto.createUser(parts["key"], parts["algo"]):
        session.insertPage(ui.initUser(clnt, crypto.pubKey), crypto.pubKey)
    else:
      session.insertPage(ui.initMessage("You must log out of your existing account before logging in to a new one."), "message")

proc insertHash*(session: var auto, hash: string) =
  session.insert(Global, Hash, hash)
  session.fireRules

proc initSession*(clnt: client.Client): auto =
  result = initSession(Fact, autoFire = false)
  for r in rules.fields:
    result.add(r)
  result.insert(Global, Board, paths.sysopPublicKey)
  result.insert(Global, Client, clnt)
  result.insert(Global, Hash, "")
  result.insert(Global, SelectedPage, "")
  result.insert(Global, AllPages, cast[PageTable](nil))
  let empty: StringSeq = @[]
  result.insert(Global, PageBreadcrumbs, empty)
  result.insert(Global, PageBreadcrumbsIndex, -1)
  result.insert(Global, Drafts, false)
  var hash =
    when defined(emscripten):
      emscripten.getHash()
    else:
      ""
  if hash == "":
    hash = "board:" & paths.sysopPublicKey
  result.routeHash(clnt, hash)
  result.fireRules

proc refresh(session: var auto, clnt: client.Client, page: Page) =
  session.insert(page.id, FocusIndex, 0)
  session.insert(page.id, ScrollY, 0)
  session.insert(page.id, View, cast[JsonNode](nil))
  ui.refresh(clnt, page.data)

proc handleAction(session: var auto, clnt: client.Client, comp: ui.Component, width: int, height: int, input: tuple[key: iw.Key, codepoint: uint32], actionName: string, actionData: OrderedTable[string, JsonNode]): bool =
  case actionName:
  of "show-post":
    result = input.key in (when defined(emscripten): {iw.Key.Mouse, iw.Key.Enter} else: {iw.Key.Mouse, iw.Key.Enter, iw.Key.Right})
    if result:
      let
        typ = actionData["type"].str
        sig = actionData["sig"].str
        globals = session.query(rules.getGlobals)
        comp =
          if typ == "user" or sig == crypto.pubKey:
            ui.initUser(clnt, sig)
          else:
            ui.initPost(clnt, sig)
      session.insertPage(comp, sig)
  of "change-page":
    result = input.key in (when defined(emscripten): {iw.Key.Mouse, iw.Key.Enter} else: {iw.Key.Mouse, iw.Key.Enter, iw.Key.Right})
    if result:
      let
        change = actionData["offset-change"].num.int
        globals = session.query(rules.getGlobals)
        page = globals.pages[globals.selectedPage]
      page.data.offset += change
      refresh(session, clnt, page)
  of "show-editor":
    result = input.key in (when defined(emscripten): {iw.Key.Mouse, iw.Key.Enter} else: {iw.Key.Mouse, iw.Key.Enter, iw.Key.Right})
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
        session.insertPage(ui.initEditor(width, height, sig, headers), sig)
  of "toggle-user-posts":
    result = input.key in (when defined(emscripten): {iw.Key.Mouse, iw.Key.Enter} else: {iw.Key.Mouse, iw.Key.Enter, iw.Key.Right})
    if result:
      let
        key = actionData["key"].str
        globals = session.query(rules.getGlobals)
      if globals.pages.hasKey(key):
        let page = globals.pages[key]
        page.data.showAllPosts = not page.data.showAllPosts
        page.data.offset = 0
        refresh(session, clnt, page)
  of "edit":
    result = input.key notin {iw.Key.Escape}
  of "go-back":
    result = input.key in {iw.Key.Mouse, iw.Key.Enter}
    if result:
      let globals = session.query(rules.getGlobals)
      if globals.breadcrumbsIndex > 0:
        session.insert(Global, PageBreadcrumbsIndex, globals.breadcrumbsIndex - 1)
  of "create-user":
    result = input.key in {iw.Key.Mouse, iw.Key.Enter}
    if result:
      crypto.createUser()
      let globals = session.query(rules.getGlobals)
      session.insert(Global, PageBreadcrumbsIndex, globals.breadcrumbsIndex - 1)
  of "login":
    when defined(emscripten):
      result = input.key in {iw.Key.Mouse, iw.Key.Enter}
      if result:
        var sess = session
        crypto.browsePrivateKey(proc () =
          let globals = sess.query(rules.getGlobals)
          if globals.breadcrumbsIndex > 0:
            sess.insert(Global, PageBreadcrumbsIndex, globals.breadcrumbsIndex - 1)
        )
  of "logout":
    result = input.key in {iw.Key.Mouse, iw.Key.Enter}
    if result:
      crypto.removeKey()
      let globals = session.query(rules.getGlobals)
      if globals.breadcrumbsIndex > 0:
        session.insert(Global, PageBreadcrumbsIndex, globals.breadcrumbsIndex - 1)
        session.fireRules
        let
          globals = session.query(rules.getGlobals)
          page = globals.pages[globals.selectedPage]
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
  let
    globals = session.query(rules.getGlobals)
    page = globals.pages[globals.selectedPage]
  page.isEditor

proc init*() =
  try:
    crypto.loadKey()
  except Exception as ex:
    echo ex.msg

  when defined(emscripten):
    midi.fetchSoundfont()

  # remove old cached files
  const deleteFromStorageSeconds = 60 * 60 # 1 hour
  for filename in storage.list():
    if strutils.endsWith(filename, ".ansiwave"):
      var parsed = post.Parsed(kind: post.Local)
      post.parseAnsiwave(storage.get(filename), parsed)
      if parsed.kind != post.Error and times.toUnix(times.getTime()) - deleteFromStorageSeconds >= post.getTime(parsed):
        storage.remove(filename)

const nonCachedPages = ["drafts", "message"].toHashSet

proc render*(session: var auto, clnt: client.Client, width: int, height: int, input: tuple[key: iw.Key, codepoint: uint32], finishedLoading: var bool): iw.TerminalBuffer =
  session.fireRules
  let
    globals = session.query(rules.getGlobals)
    page = globals.pages[globals.selectedPage]
    maxScroll = max(1, int(height / 5))
    view =
      if page.view == nil:
        let v = ui.toJson(page.data, finishedLoading)
        if finishedLoading and page.sig notin nonCachedPages:
          session.insert(page.id, View, v)
          var cmds: CommandTreesRef
          new cmds
          cmds[] = post.linesToTrees(strutils.splitLines(ui.getContent(page.data)))
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
  if (input.key != iw.Key.None or input.codepoint > 0) and page.focusIndex < page.viewFocusAreas.len:
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
            break
    else:
      let area = page.viewFocusAreas[page.focusIndex]
      action = (area.action, area.actionData)

  # handle the action
  if not handleAction(session, clnt, page.data, width, height, input, action.actionName, action.actionData):
    case input.key:
    of iw.Key.Up:
      if page.focusIndex > 0:
        focusIndex = page.focusIndex - 1
    of iw.Key.Down:
      focusIndex = page.focusIndex + 1
    else:
      if not isPlaying and input.key in (when defined(emscripten): {iw.Key.Escape} else: {iw.Key.Left, iw.Key.Escape}):
        backAction()
        # since we have changed the page, we need to rerun this function from the beginning
        return render(session, clnt, width, height, (iw.Key.None, 0'u32), finishedLoading)
    # adjust focusIndex and scrollY based on viewFocusAreas
    if page.viewFocusAreas.len > 0:
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
    editor.tick(page.data.session, result, 0, navbar.height, width, height - navbar.height, input, finishedLoading)
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
              page.sig[0 ..< idx]
            # go to the new sig
            else:
              page.data.requestSig
        if storage.set(sig & ".ansiwave", page.data.requestBody):
          session.insertPage(if sig == crypto.pubKey: ui.initUser(clnt, sig) else: ui.initPost(clnt, sig), sig)
        return render(session, clnt, width, height, (iw.Key.None, 0'u32), finishedLoading)
      else:
        let continueAction = proc () =
          page.data.request.chan = nil
          editor.setEditable(page.data.session, true)
        rightButtons.add((" continue editing ", continueAction))
        errorLines = @["Error", page.data.request.value.error]
    else:
      let
        sendAction = proc () {.closure.} =
          editor.setEditable(page.data.session, false)
          let (body, sig) = common.sign(crypto.keyPair, page.data.headers, editor.getContent(page.data.session))
          page.data.requestBody = body
          page.data.requestSig = sig
          page.data.request = client.submit(clnt, "ansiwave", body)
      rightButtons.add((" send ", sendAction))
    if not isPlaying:
      var leftButtons: seq[(string, proc ())]
      when not defined(emscripten):
        leftButtons.add((" ← ", backAction))
      navbar.render(result, 0, 0, input, leftButtons, errorLines, rightButtons)
    page.data.session.fireRules
    editor.saveToStorage(page.data.session, page.sig)
  else:
    result = iw.newTerminalBuffer(width, when defined(emscripten): page.viewHeight else: height)
    ui.render(result, view, 0, y, focusIndex, areas)
    let
      refreshAction = proc () {.closure.} =
        refresh(sess, clnt, page)
      searchAction = proc () {.closure.} =
        discard
    var leftButtons: seq[(string, proc ())]
    when not defined(emscripten):
      leftButtons &= @[(" ← ", backAction), (" ⟳ ", refreshAction)]
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
          editor.copyLink("https://ansiwave.net/#" & globals.hash)
          # redraw ui without double buffering so everything is visible again
          iw.setDoubleBuffering(false)
          var finishedLoading: bool
          discard render(sess, clnt, width, height, (iw.Key.None, 0'u32), finishedLoading)
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
                if midiResult.secs > 0:
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
        elif crypto.pubKey == "":
          let
            loginAction = proc () {.closure.} =
              sess.insertPage(ui.initLogin(), "login")
          @[(" login ", loginAction)]
        elif page.sig == crypto.pubKey:
          let
            logoutAction = proc () {.closure, gcsafe.} =
              {.cast(gcsafe).}:
                sess.insertPage(ui.initLogout(), "logout")
            downloadKeyAction = proc () {.closure.} =
              when defined(emscripten):
                crypto.downloadImage()
          when defined(emscripten):
            @[(" download login key ", downloadKeyAction), (" logout ", logoutAction)]
          else:
            @[(" logout ", logoutAction)]
        else:
          let
            draftsAction = proc () {.closure.} =
              sess.insertPage(ui.initDrafts(clnt), "drafts")
            myPageAction = proc () {.closure.} =
              sess.insertPage(ui.initUser(clnt, crypto.pubKey), crypto.pubKey)
          if globals.drafts and page.sig != "drafts":
            @[(" drafts ", draftsAction), (" my page ", myPageAction)]
          else:
            @[(" my page ", myPageAction)]
      navbar.render(result, 0, 0, input, leftButtons, [], rightButtons)
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
        return render(session, clnt, width, height, (iw.Key.None, 0'u32), finishedLoading)

proc renderBBS*() =
  vfs.readUrl = "http://localhost:" & $paths.port & "/" & paths.boardsDir & "/" & paths.sysopPublicKey & "/" & paths.dbDir & "/" & paths.dbFilename
  vfs.register()
  var clnt = client.initClient(paths.address, paths.postAddress)
  client.start(clnt)

  # create session
  var session = initSession(clnt)

  init()

  # start loop
  while true:
    var finishedLoading = false
    var tb = render(session, clnt, iw.terminalWidth(), iw.terminalHeight(), (iw.getKey(), 0'u32), finishedLoading)
    # display and sleep
    iw.display(tb)
    os.sleep(constants.sleepMsecs)

