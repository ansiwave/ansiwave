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
    ScrollY, View, ViewHeight,
  ComponentRef = ref ui.Component

schema Fact(Id, Attr):
  SelectedColumn: int
  ComponentData: ComponentRef
  FocusIndex: int
  ScrollY: int
  View: JsonNode
  ViewHeight: int

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
    renderedFocusIndex =
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
  result = iw.newTerminalBuffer(width, bufferHeight)
  var
    y = 0
    blocks: seq[tuple[top: int, bottom: int]]
  let view =
    if comp.view != nil:
      finishedLoading = true
      comp.view
    else:
      let v = ui.toJson(comp.data[], finishedLoading)
      if finishedLoading:
        session.insert(comp.id, View, v)
      v
  ui.render(result, view, 0, y, key, comp.scrollY, renderedFocusIndex, blocks)
  # update the view height if it has increased
  if blocks.len > 0 and blocks[blocks.len - 1].bottom > comp.viewHeight:
    session.insert(comp.id, ViewHeight, blocks[blocks.len - 1].bottom)
  var focusIndex = renderedFocusIndex
  # adjust scroll and reset focusIndex if necessary
  if blocks.len > 0:
    if focusIndex > blocks.len - 1:
      focusIndex = blocks.len - 1
    case key:
    of iw.Key.Up:
      if blocks[focusIndex].top < comp.scrollY:
        let limit = comp.scrollY - maxScroll
        if blocks[focusIndex].top < limit:
          session.insert(comp.id, ScrollY, limit)
          for i in 0 .. blocks.len - 1:
            if blocks[i].bottom > limit:
              focusIndex = i
              break
        else:
          session.insert(comp.id, ScrollY, blocks[focusIndex].top)
    of iw.Key.Down:
      if blocks[focusIndex].bottom > comp.scrollY + height:
        let limit = comp.scrollY + maxScroll
        if blocks[focusIndex].bottom - height > limit:
          session.insert(comp.id, ScrollY, limit)
          for i in countdown(blocks.len - 1, 0):
            if blocks[i].top < limit + height:
              focusIndex = i
              break
        else:
          session.insert(comp.id, ScrollY, blocks[focusIndex].bottom - height)
    else:
      discard
  if focusIndex != comp.focusIndex:
    session.insert(comp.id, FocusIndex, focusIndex)
  # if focusIndex was reset, re-render so the correct block has the double lines
  if focusIndex != renderedFocusIndex:
    y = 0
    blocks = @[]
    ui.render(result, view, 0, y, key, comp.scrollY, focusIndex, blocks)
  let scrollY = session.query(rules.getSelectedColumn).scrollY
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

