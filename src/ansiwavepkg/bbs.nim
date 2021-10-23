from ./illwill as iw import `[]`, `[]=`
from wavecorepkg/db/vfs import nil
from wavecorepkg/db/entities import nil
from wavecorepkg/client import nil
from os import nil
from ./ui import nil
from ./constants import nil
import pararules

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
  ComponentRef = ref ui.Component

schema Fact(Id, Attr):
  SelectedColumn: int
  ComponentData: ComponentRef
  FocusIndex: int
  ScrollY: int

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

proc insert(session: var auto, comp: ui.Component) =
  let col = session.query(rules.getGlobals).selectedColumn
  var compRef: ComponentRef
  new compRef
  compRef[] = comp
  session.insert(col, ComponentData, compRef)
  session.insert(col, FocusIndex, 0)
  session.insert(col, ScrollY, 0)

proc render(session: var auto, comp: tuple): iw.TerminalBuffer =
  let
    width = iw.terminalWidth()
    height = iw.terminalHeight()
    key = iw.getKey()
    #maxScroll = 10
    bufferHeight = height * 2
  result = iw.newTerminalBuffer(width, bufferHeight)
  var
    y = 0
    focus = (index: 0, top: 0, bottom: 0)
    focusIndex = comp.focusIndex
  case key:
  of iw.Key.Up:
    if focusIndex > 0:
      focusIndex -= 1
      session.insert(comp.id, FocusIndex, focusIndex)
  of iw.Key.Down:
    focusIndex += 1
    session.insert(comp.id, FocusIndex, focusIndex)
  else:
    discard
  ui.render(result, ui.toJson(comp.data[]), 0, y, key, focusIndex, focus)
  case key:
  of iw.Key.Up:
    if focus.top < comp.scrollY:
      #session.insert(comp.id, ScrollY, max(comp.scrollY - maxScroll, focus.top))
      session.insert(comp.id, ScrollY, focus.top)
  of iw.Key.Down:
    if focus.bottom > comp.scrollY + height:
      #session.insert(comp.id, ScrollY, min(comp.scrollY + maxScroll, focus.bottom - height))
      session.insert(comp.id, ScrollY, focus.bottom - height)
    if focusIndex > focus.index:
      session.insert(comp.id, FocusIndex, focus.index)
  else:
    discard
  let scrollY = session.query(rules.getSelectedColumn).scrollY
  result.height = height
  result.buf = result.buf[scrollY * width ..< result.buf.len]
  result.buf = result.buf[0 ..< height * width]

proc renderBBS*() =
  vfs.readUrl = "http://localhost:" & $port & "/" & ui.dbFilename
  vfs.register()
  var c = client.initClient(address)
  client.start(c)

  # create session
  var session = initSession(Fact, autoFire = false)
  for r in rules.fields:
    session.add(r)
  session.insert(Global, SelectedColumn, 0)
  session.insert(ui.initPost(c, 1))

  # start loop
  while true:
    session.fireRules
    let comp = session.query(rules.getSelectedColumn)
    var tb = render(session, comp)
    # display and sleep
    iw.display(tb)
    os.sleep(constants.sleepMsecs)

