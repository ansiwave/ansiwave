from ./illwill as iw import `[]`, `[]=`
from wavecorepkg/db/vfs import nil
from wavecorepkg/client import nil
from os import nil
from ./ui import nil
from ./constants import nil
import pararules
from json import JsonNode
import tables

const
  port = 3000
  address = "http://localhost:" & $port

type
  Id* = enum
    Global,
  Attr* = enum
    SelectedPage, AllPages,
    ComponentData, FocusIndex, ScrollY,
    View, ViewHeight, ViewFocusAreas,
  ComponentRef = ref ui.Component
  ViewFocusAreasType = seq[tuple[top: int, bottom: int]]
  Page = tuple
    id: int
    data: ComponentRef
    focusIndex: int
    scrollY: int
    view: JsonNode
    viewHeight: int
    viewFocusAreas: ViewFocusAreasType
  Pages = ref Table[int, Page]

schema Fact(Id, Attr):
  SelectedPage: int
  AllPages: Pages
  ComponentData: ComponentRef
  FocusIndex: int
  ScrollY: int
  View: JsonNode
  ViewHeight: int
  ViewFocusAreas: ViewFocusAreasType

let rules =
  ruleset:
    rule getGlobals(Fact):
      what:
        (Global, SelectedPage, selectedPage)
        (Global, AllPages, pages)
    rule getPage(Fact):
      what:
        (id, ComponentData, data)
        (id, FocusIndex, focusIndex)
        (id, ScrollY, scrollY)
        (id, View, view)
        (id, ViewHeight, viewHeight)
        (id, ViewFocusAreas, viewFocusAreas)
      thenFinally:
        var t: Pages
        new t
        for page in session.queryAll(this):
          t[page.id] = page
        session.insert(Global, AllPages, t)

proc insert(session: var auto, comp: ui.Component, id: int) =
  var compRef: ComponentRef
  new compRef
  compRef[] = comp
  session.insert(id, ComponentData, compRef)
  session.insert(id, FocusIndex, 0)
  session.insert(id, ScrollY, 0)
  session.insert(id, View, cast[JsonNode](nil))
  session.insert(id, ViewHeight, 0)
  session.insert(id, ViewFocusAreas, @[])

proc initSession*(c: client.Client): auto =
  result = initSession(Fact, autoFire = false)
  for r in rules.fields:
    result.add(r)
  let id = 1
  result.insert(Global, SelectedPage, id)
  result.insert(ui.initPost(c, id), id)

proc render*(session: var auto, width: int, height: int, key: iw.Key, finishedLoading: var bool): iw.TerminalBuffer =
  session.fireRules
  let
    globals = session.query(rules.getGlobals)
    page = globals.pages[globals.selectedPage]
    bufferHeight = max(page.viewHeight, height)
    maxScroll = max(1, int(height / 5))
    view =
      if page.view != nil:
        finishedLoading = true
        page.view
      else:
        let v = ui.toJson(page.data[], finishedLoading)
        if finishedLoading:
          session.insert(page.id, View, v)
        v
  result = iw.newTerminalBuffer(width, bufferHeight)
  var
    focusIndex =
      case key:
      of iw.Key.Up:
        if page.focusIndex > 0:
          page.focusIndex - 1
        else:
          page.focusIndex
      of iw.Key.Down:
        page.focusIndex + 1
      else:
        page.focusIndex
    scrollY = page.scrollY
  # adjust focusIndex and scrollY based on viewFocusAreas
  if page.viewFocusAreas.len > 0:
    # don't let it go beyond the last focused area
    if focusIndex > page.viewFocusAreas.len - 1:
      focusIndex = page.viewFocusAreas.len - 1
    # when going up or down, if the next focus area's edge is
    # beyond the current viewable scroll area, adjust scrollY
    # so we can see it. if the adjustment is greater than maxScroll,
    # only scroll maxScroll rows and update the focusIndex.
    case key:
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
  # update values if necessary
  if focusIndex != page.focusIndex:
    session.insert(page.id, FocusIndex, focusIndex)
  if scrollY != page.scrollY:
    session.insert(page.id, ScrollY, scrollY)
  # render
  var
    y = 0
    blocks: seq[tuple[top: int, bottom: int]]
  ui.render(result, view, 0, y, key, scrollY, focusIndex, blocks)
  # update the view height if it has increased
  if blocks.len > 0 and blocks[blocks.len - 1].bottom > page.viewHeight:
    session.insert(page.id, ViewHeight, blocks[blocks.len - 1].bottom)
    session.insert(page.id, ViewFocusAreas, blocks)
  # adjust buffer so part above the scroll line isn't visible
  if (scrollY + height) <= bufferHeight:
    result.height = height
    result.buf = result.buf[scrollY * width ..< result.buf.len]
    result.buf = result.buf[0 ..< height * width]

proc renderBBS*() =
  vfs.readUrl = "http://localhost:" & $port & "/" & ui.dbFilename
  vfs.register()
  var c = client.initClient(address)
  client.start(c)

  # create session
  var session = initSession(c)

  # start loop
  while true:
    var finishedLoading = false
    var tb = render(session, iw.terminalWidth(), iw.terminalHeight(), iw.getKey(), finishedLoading)
    # display and sleep
    iw.display(tb)
    os.sleep(constants.sleepMsecs)

