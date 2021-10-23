from illwill as iw import `[]`, `[]=`
from wavecorepkg/db/vfs import nil
from wavecorepkg/client import nil
from os import nil
from ./ui import nil
from ./constants import nil

const
  port = 3000
  address = "http://localhost:" & $port

proc renderBBS*() =
  vfs.readUrl = "http://localhost:" & $port & "/" & ui.dbFilename
  vfs.register()
  var c = client.initClient(address)
  client.start(c)
  var post = ui.init[ui.Post](c, 1)
  while true:
    let
      width = iw.terminalWidth()
      height = iw.terminalHeight()
      key = iw.getKey()
    var tb = iw.newTerminalBuffer(width, height)
    ui.render(tb, post, key)
    # display and sleep
    iw.display(tb)
    os.sleep(constants.sleepMsecs)

