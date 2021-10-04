from illwill as iw import `[]`, `[]=`
from wavecorepkg/db import nil
from wavecorepkg/db/entities import nil
from wavecorepkg/db/db_sqlite import nil
import wavecorepkg/db/vfs
from wavecorepkg/server import nil
from wavecorepkg/client import nil
from os import nil
from strutils import format
import constants

const
  filename = "tests/bbs/board.db"
  port = 3000
  address = "http://localhost:" & $port

var s = server.initServer("localhost", port, @["."])
server.start(s)
var c = client.initClient(address)
client.start(c)
var response: ptr Channel[client.Result[seq[entities.Post]]]

proc init() =
  vfs.readUrl = "http://localhost:" & $port & "/" & filename
  # create test db
  if os.fileExists(filename):
    os.removeFile(filename)
  var conn = db.open(filename)
  db.init(conn)
  var p1 = entities.Post(parent_id: 0, user_id: 0, body: "Hello, world!")
  p1.id = entities.insertPost(conn, p1)
  var
    alice = entities.User(username: "Alice", public_key: "stuff")
    bob = entities.User(username: "Bob", public_key: "asdf")
  alice.id = entities.insertUser(conn, alice)
  bob.id = entities.insertUser(conn, bob)
  var p2 = entities.Post(parent_id: p1.id, user_id: bob.id, body: "Hello, i'm bob")
  p2.id = entities.insertPost(conn, p2)
  var p3 = entities.Post(parent_id: p2.id, user_id: alice.id, body: "What's up")
  p3.id = entities.insertPost(conn, p3)
  db_sqlite.close(conn)

proc renderBBS*() =
  init()
  response = client.queryPostChildren(c, filename, 1)
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
    if response != nil:
      let res = response[].tryRecv()
      if res.dataAvailable:
        echo res.msg
        server.stop(s)
        client.stop(c)
        response = nil

