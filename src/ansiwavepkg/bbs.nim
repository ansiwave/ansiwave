from illwill as iw import `[]`, `[]=`
from wavecorepkg/db/vfs import nil
from wavecorepkg/server import nil
from wavecorepkg/client import nil
from os import joinPath
from strutils import format
import constants
import unicode
from codes import nil

const
  port = 3000
  address = "http://localhost:" & $port

let
  staticFileDir = "tests".joinPath("bbs")
  dbPath = staticFileDir.joinPath(server.dbFilename)

var c = client.initClient(address)
client.start(c)

proc renderBBS*(tb: var iw.TerminalBuffer, root: var auto, threads: var auto) =
  var screenLine = 0
  client.get(root)
  if root.ready:
    let lines = strutils.splitLines(root.value.valid.body)
    iw.drawRect(tb, 0, 0, editorWidth, lines.len + 1, doubleStyle = true)
    for line in lines:
      var runes = line.toRunes
      codes.deleteAfter(runes, editorWidth - 1)
      codes.write(tb, 1, 1 + screenLine, $runes)
      screenLine += 1
  screenLine += 2
  client.get(threads)
  if threads.ready:
    for post in threads.value.valid:
      let lines = strutils.splitLines(post.body.uncompressed)
      iw.drawRect(tb, 0, screenLine, editorWidth, 1 + screenLine + lines.len, doubleStyle = false)
      screenLine += 1
      for line in lines:
        iw.write(tb, 1, screenLine, line)
        screenLine += 2

proc renderBBS*() =
  vfs.readUrl = "http://localhost:" & $port & "/" & server.dbFilename
  vfs.register()
  var
    root = client.query(c, server.ansiwavesDir.joinPath("1.ansiwavez"))
    threads = client.queryPostChildren(c, server.dbFilename, 1)
  while true:
    let
      width = iw.terminalWidth()
      height = iw.terminalHeight()
    var tb = iw.newTerminalBuffer(width, height)
    renderBBS(tb, root, threads)
    # display and sleep
    iw.display(tb)
    os.sleep(sleepMsecs)

