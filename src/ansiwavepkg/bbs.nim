from ./illwill as iw import `[]`, `[]=`
from wavecorepkg/db/vfs import nil
from wavecorepkg/client import nil
from os import nil
from ./ui import nil
from ./ui/editor import nil
from ./constants import nil
import pararules
from pararules/engine import Session, Vars
from json import JsonNode
import tables

const
  port = 3000
  address = "http://localhost:" & $port

type
  Id* = enum
    Global,
  Attr* = enum
    SelectedPage, AllPages, PageBreadcrumbs, PageBreadcrumbsIndex,
    ComponentData, FocusIndex, ScrollY,
    View, ViewHeight, ViewFocusAreas,
  ComponentRef = ref ui.Component
  ViewFocusAreaSeq = seq[ui.ViewFocusArea]
  Page = tuple
    id: int
    data: ComponentRef
    focusIndex: int
    scrollY: int
    view: JsonNode
    viewHeight: int
    viewFocusAreas: ViewFocusAreaSeq
  PageTable = ref Table[int, Page]
  PageBreadcrumbsType = seq[int]

schema Fact(Id, Attr):
  SelectedPage: int
  AllPages: PageTable
  PageBreadcrumbs: PageBreadcrumbsType
  PageBreadcrumbsIndex: int
  ComponentData: ComponentRef
  FocusIndex: int
  ScrollY: int
  View: JsonNode
  ViewHeight: int
  ViewFocusAreas: ViewFocusAreaSeq

type
  BbsSession* = Session[Fact, Vars[Fact]]

let rules =
  ruleset:
    rule getGlobals(Fact):
      what:
        (Global, SelectedPage, selectedPage)
        (Global, AllPages, pages)
        (Global, PageBreadcrumbs, breadcrumbs)
        (Global, PageBreadcrumbsIndex, breadcrumbsIndex)
    rule changeSelectedPage(Fact):
      what:
        (Global, PageBreadcrumbs, breadcrumbs)
        (Global, PageBreadcrumbsIndex, breadcrumbsIndex)
      then:
        session.insert(Global, SelectedPage, breadcrumbs[breadcrumbsIndex])
    rule getPage(Fact):
      what:
        (id, ComponentData, data)
        (id, FocusIndex, focusIndex)
        (id, ScrollY, scrollY)
        (id, View, view)
        (id, ViewHeight, viewHeight)
        (id, ViewFocusAreas, viewFocusAreas)
      thenFinally:
        var t: PageTable
        new t
        for page in session.queryAll(this):
          t[page.id] = page
        session.insert(Global, AllPages, t)

proc goToPage(session: var auto, id: int) =
  var globals = session.query(rules.getGlobals)
  var breadcrumbs = globals.breadcrumbs
  if globals.breadcrumbsIndex < breadcrumbs.len - 1:
    breadcrumbs = breadcrumbs[0 .. globals.breadcrumbsIndex]
  breadcrumbs.add(id)
  session.insert(Global, PageBreadcrumbs, breadcrumbs)
  session.insert(Global, PageBreadcrumbsIndex, globals.breadcrumbsIndex + 1)

proc insertPage(session: var auto, comp: ui.Component, id: int) =
  var compRef: ComponentRef
  new compRef
  compRef[] = comp
  session.insert(id, ComponentData, compRef)
  session.insert(id, FocusIndex, 0)
  session.insert(id, ScrollY, 0)
  session.insert(id, View, cast[JsonNode](nil))
  session.insert(id, ViewHeight, 0)
  session.insert(id, ViewFocusAreas, @[])
  session.goToPage(id)

proc initSession*(c: client.Client): auto =
  result = initSession(Fact, autoFire = false)
  for r in rules.fields:
    result.add(r)
  result.insert(Global, SelectedPage, -1)
  result.insert(Global, AllPages, cast[PageTable](nil))
  let breadcrumbs: PageBreadcrumbsType = @[]
  result.insert(Global, PageBreadcrumbs, breadcrumbs)
  result.insert(Global, PageBreadcrumbsIndex, -1)
  result.insertPage(ui.initPost(c, 1), 1)
  result.fireRules

proc handleAction(session: var auto, clnt: client.Client, comp: var ui.Component, input: tuple[key: iw.Key, codepoint: uint32], actionName: string, actionData: OrderedTable[string, JsonNode]): bool =
  case actionName:
  of "show-replies":
    result = input.key in {iw.Key.Mouse, iw.Key.Enter, iw.Key.Right}
    if result:
      let
        id = actionData["id"].num.int
        globals = session.query(rules.getGlobals)
      if globals.breadcrumbsIndex < globals.breadcrumbs.len - 1 and globals.breadcrumbs[globals.breadcrumbsIndex + 1] == id:
        session.insert(Global, PageBreadcrumbsIndex, globals.breadcrumbsIndex + 1)
      else:
        if globals.pages.hasKey(id):
          session.goToPage(id)
        else:
          session.insertPage(ui.initPost(clnt, id), id)
#[
  of "edit":
    let buffer = editor.getEditor(comp.replyEditor)
    if input.key == iw.Key.None:
      result = editor.onInput(comp.replyEditor, input.codepoint, buffer)
    else:
      result = editor.onInput(comp.replyEditor, input.key, buffer) or editor.onInput(comp.replyEditor, input.key.ord.uint32, buffer)
]#
  else:
    discard

proc renderHtml*(session: auto): string =
  let
    globals = session.query(rules.getGlobals)
    page = globals.pages[globals.selectedPage]
  ui.toHtml(page.data[])

proc render*(session: var auto, clnt: client.Client, width: int, height: int, input: tuple[key: iw.Key, codepoint: uint32], finishedLoading: var bool): iw.TerminalBuffer =
  session.fireRules
  let
    globals = session.query(rules.getGlobals)
    page = globals.pages[globals.selectedPage]
    maxScroll = max(1, int(height / 5))
    view = ui.toJson(page.data[], finishedLoading)
  if finishedLoading:
    session.insert(page.id, View, view)
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
              info.y + scrollY <= area.bottom - 1:
            action = (area.action, area.actionData)
            focusIndex = i
            break
    else:
      let area = page.viewFocusAreas[page.focusIndex]
      action = (area.action, area.actionData)
  # handle the action
  if not handleAction(session, clnt, page.data[], input, action.actionName, action.actionData):
    case input.key:
    of iw.Key.Up:
      if page.focusIndex > 0:
        focusIndex = page.focusIndex - 1
    of iw.Key.Down:
      focusIndex = page.focusIndex + 1
    of iw.Key.Left:
      if globals.breadcrumbsIndex > 0:
        session.insert(Global, PageBreadcrumbsIndex, globals.breadcrumbsIndex - 1)
        # since we have changed the page, we need to rerun this function from the beginning
        return render(session, clnt, width, height, (iw.Key.None, 0'u32), finishedLoading)
    else:
      discard
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
        if page.viewFocusAreas[focusIndex].top < page.scrollY:
          scrollY = page.viewFocusAreas[focusIndex].top
          let limit = page.scrollY - maxScroll
          if scrollY < limit:
            scrollY = limit
            for i in 0 .. page.viewFocusAreas.len - 1:
              if page.viewFocusAreas[i].bottom > limit:
                focusIndex = i
                break
      of iw.Key.Down:
        if page.viewFocusAreas[focusIndex].bottom > page.scrollY + height:
          scrollY = page.viewFocusAreas[focusIndex].bottom - height
          let limit = page.scrollY + maxScroll
          if scrollY > limit:
            scrollY = limit
            for i in countdown(page.viewFocusAreas.len - 1, 0):
              if page.viewFocusAreas[i].top < limit + height:
                focusIndex = i
                break
      else:
        discard
  # render
  var
    y = - scrollY
    areas: seq[ui.ViewFocusArea]
  result = iw.newTerminalBuffer(width, when defined(emscripten): page.viewHeight else: height)
  ui.render(result, view, 0, y, focusIndex, areas)
  # update values if necessary
  if focusIndex != page.focusIndex:
    session.insert(page.id, FocusIndex, focusIndex)
  if scrollY != page.scrollY:
    session.insert(page.id, ScrollY, scrollY)
  # update the view height if it has increased
  # don't do this after scrolling, or the values will be incorrect
  if y > page.viewHeight and scrollY == 0:
    session.insert(page.id, ViewHeight, y)
    session.insert(page.id, ViewFocusAreas, areas)
    # if the view height has changed, emscripten needs to render again
    when defined(emscripten):
      return render(session, clnt, width, height, (iw.Key.None, 0'u32), finishedLoading)

proc renderBBS*() =
  vfs.readUrl = "http://localhost:" & $port & "/" & ui.dbFilename
  vfs.register()
  var clnt = client.initClient(address)
  client.start(clnt)

  # create session
  var session = initSession(clnt)

  # start loop
  while true:
    var finishedLoading = false
    var tb = render(session, clnt, iw.terminalWidth(), iw.terminalHeight(), (iw.getKey(), 0'u32), finishedLoading)
    # display and sleep
    iw.display(tb)
    os.sleep(constants.sleepMsecs)

