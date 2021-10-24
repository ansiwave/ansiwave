from ./illwill as iw import `[]`, `[]=`
from wavecorepkg/db/vfs import nil
from wavecorepkg/client import nil
from os import nil
from ./ui import nil
from ./constants import nil
import pararules
from json import JsonNode

const
  port = 3000
  address = "http://localhost:" & $port

type
  Id* = enum
    Global,
  Attr* = enum
    SelectedColumn,
    ComponentData, FocusIndex,
    ScrollY,
    View, ViewHeight, ViewFocusAreas,
  ComponentRef = ref ui.Component
  ViewFocusAreasType = seq[tuple[top: int, bottom: int]]

schema Fact(Id, Attr):
  SelectedColumn: int
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
        (Global, SelectedColumn, selectedColumn)
    rule getSelectedColumn(Fact):
      what:
        (Global, SelectedColumn, id)
        (id, ComponentData, data)
        (id, FocusIndex, focusIndex)
        (id, ScrollY, scrollY)
        (id, View, view)
        (id, ViewHeight, viewHeight)
        (id, ViewFocusAreas, viewFocusAreas)

proc insert(session: var auto, comp: ui.Component) =
  let col = session.query(rules.getGlobals).selectedColumn
  var compRef: ComponentRef
  new compRef
  compRef[] = comp
  session.insert(col, ComponentData, compRef)
  session.insert(col, FocusIndex, 0)
  session.insert(col, ScrollY, 0)
  session.insert(col, View, cast[JsonNode](nil))
  session.insert(col, ViewHeight, 0)
  session.insert(col, ViewFocusAreas, @[])

proc initSession*(c: client.Client): auto =
  result = initSession(Fact, autoFire = false)
  for r in rules.fields:
    result.add(r)
  result.insert(Global, SelectedColumn, 0)
  result.insert(ui.initPost(c, 1))

proc render*(session: var auto, width: int, height: int, key: iw.Key, finishedLoading: var bool): iw.TerminalBuffer =
  let
    comp = session.query(rules.getSelectedColumn)
    bufferHeight = max(comp.viewHeight, iw.terminalHeight())
    maxScroll = max(1, int(height / 5))
    view =
      if comp.view != nil:
        finishedLoading = true
        comp.view
      else:
        let v = ui.toJson(comp.data[], finishedLoading)
        if finishedLoading:
          session.insert(comp.id, View, v)
        v
  result = iw.newTerminalBuffer(width, bufferHeight)
  var
    focusIndex =
      case key:
      of iw.Key.Up:
        if comp.focusIndex > 0:
          comp.focusIndex - 1
        else:
          comp.focusIndex
      of iw.Key.Down:
        comp.focusIndex + 1
      else:
        comp.focusIndex
    scrollY = comp.scrollY
  # adjust focusIndex and scrollY based on viewFocusAreas
  if comp.viewFocusAreas.len > 0:
    # don't let it go beyond the last focused area
    if focusIndex > comp.viewFocusAreas.len - 1:
      focusIndex = comp.viewFocusAreas.len - 1
    # when going up or down, if the next focus area's edge is
    # beyond the current viewable scroll area, adjust scrollY
    # so we can see it. if the adjustment is greater than maxScroll,
    # only scroll maxScroll rows and update the focusIndex.
    case key:
    of iw.Key.Up:
      if comp.viewFocusAreas[focusIndex].top < comp.scrollY:
        scrollY = comp.viewFocusAreas[focusIndex].top
        let limit = comp.scrollY - maxScroll
        if scrollY < limit:
          scrollY = limit
          for i in 0 .. comp.viewFocusAreas.len - 1:
            if comp.viewFocusAreas[i].bottom > limit:
              focusIndex = i
              break
    of iw.Key.Down:
      if comp.viewFocusAreas[focusIndex].bottom > comp.scrollY + height:
        scrollY = comp.viewFocusAreas[focusIndex].bottom - height
        let limit = comp.scrollY + maxScroll
        if scrollY > limit:
          scrollY = limit
          for i in countdown(comp.viewFocusAreas.len - 1, 0):
            if comp.viewFocusAreas[i].top < limit + height:
              focusIndex = i
              break
    else:
      discard
  # update values if necessary
  if focusIndex != comp.focusIndex:
    session.insert(comp.id, FocusIndex, focusIndex)
  if scrollY != comp.scrollY:
    session.insert(comp.id, ScrollY, scrollY)
  # render
  var
    y = 0
    blocks: seq[tuple[top: int, bottom: int]]
  ui.render(result, view, 0, y, key, scrollY, focusIndex, blocks)
  # update the view height if it has increased
  if blocks.len > 0 and blocks[blocks.len - 1].bottom > comp.viewHeight:
    session.insert(comp.id, ViewHeight, blocks[blocks.len - 1].bottom)
    session.insert(comp.id, ViewFocusAreas, blocks)
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
    session.fireRules
    var finishedLoading = false
    var tb = render(session, iw.terminalWidth(), iw.terminalHeight(), iw.getKey(), finishedLoading)
    # display and sleep
    iw.display(tb)
    os.sleep(constants.sleepMsecs)

