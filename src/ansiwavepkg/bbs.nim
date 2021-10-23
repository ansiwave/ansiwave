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
    ScrollX, ScrollY,
    ComponentData, FocusIndex,
  ComponentRef = ref ui.Component

schema Fact(Id, Attr):
  SelectedColumn: int
  ScrollX: int
  ScrollY: int
  ComponentData: ComponentRef
  FocusIndex: int

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

proc insert(session: var auto, comp: ui.Component) =
  let col = session.query(rules.getGlobals).selectedColumn
  var compRef: ComponentRef
  new compRef
  compRef[] = comp
  session.insert(col, ComponentData, compRef)
  session.insert(col, FocusIndex, 0)

proc render(session: var auto, tb: var iw.TerminalBuffer, comp: tuple, key: iw.Key) =
  var
    y = 0
    currFocusIndex = 0
  case key:
  of iw.Key.Up:
    if comp.focusIndex > 0:
      session.insert(comp.id, FocusIndex, comp.focusIndex - 1)
  of iw.Key.Down:
    session.insert(comp.id, FocusIndex, comp.focusIndex + 1)
  else:
    discard
  ui.render(tb, ui.toJson(comp.data[]), 0, y, key, comp.focusIndex, currFocusIndex)

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
    let
      width = iw.terminalWidth()
      height = iw.terminalHeight()
      key = iw.getKey()
    var tb = iw.newTerminalBuffer(width, height)
    session.fireRules
    let comp = session.query(rules.getSelectedColumn)
    render(session, tb, comp, key)
    # display and sleep
    iw.display(tb)
    os.sleep(constants.sleepMsecs)

