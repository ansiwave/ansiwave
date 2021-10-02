from illwill as iw import `[]`, `[]=`
from wavecorepkg/db import nil
from wavecorepkg/db/entities import nil
from wavecorepkg/db/db_sqlite import nil
from os import nil
from osproc import nil
from strutils import format
import constants

proc init() =
  const
    filename = "tests/bbs/board.db"
    port = "8000"
  #vfs.readUrl = "http://localhost:" & port & "/" & filename
  var process: osproc.Process = nil
  try:
    # start web server
    process = osproc.startProcess("ruby", args=["-run", "-ehttpd", "tests/bbs", "-p" & port], options={osproc.poUsePath, osproc.poStdErrToStdOut})
    os.sleep(1000)
    # create test db
    var conn = db.open(filename)
    db.init(conn)
    var
      alice = entities.User(username: "Alice", public_key: "stuff")
      bob = entities.User(username: "Bob", public_key: "asdf")
    alice.id = entities.insertUser(conn, alice)
    bob.id = entities.insertUser(conn, bob)
    var p1 = entities.Post(parent_id: 0, user_id: alice.id, body: "Hello, i'm alice")
    p1.id = entities.insertPost(conn, p1)
    var p2 = entities.Post(parent_id: p1.id, user_id: bob.id, body: "Hello, i'm bob")
    p2.id = entities.insertPost(conn, p2)
    var p3 = entities.Post(parent_id: p2.id, user_id: alice.id, body: "What's up")
    p3.id = entities.insertPost(conn, p3)
    db_sqlite.close(conn)
  finally:
    osproc.kill(process)
    os.removeFile(filename)

proc renderBBS*() =
  let
    homeText = strutils.splitLines(readFile("tests/bbs/ansiwaves/1.ansiwave"))
  while true:
    let
      width = iw.terminalWidth()
      height = iw.terminalHeight()
      x = max(0, int(width/2 - editorWidth/2))
    var
      tb = iw.newTerminalBuffer(width, height)
      y = 0
    for line in homeText:
      iw.write(tb, x, y, line)
      y.inc
    # display and sleep
    iw.display(tb)
    os.sleep(sleepMsecs)

