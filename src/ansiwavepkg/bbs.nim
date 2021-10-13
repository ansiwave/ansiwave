from illwill as iw import `[]`, `[]=`
from wavecorepkg/db import nil
from wavecorepkg/db/entities import nil
from wavecorepkg/db/db_sqlite import nil
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

var s = server.initServer("localhost", port, staticFileDir)
server.start(s)
var c = client.initClient(address)
client.start(c)
const ansiArt =
  """

                           ______                     
   _________        .---'''      '''---.              
  :______.-':      :  .--------------.  :             
  | ______  |      | :                : |             
  |:______B:|      | |   Welcome to   | |             
  |:______B:|      | |                | |             
  |:______B:|      | | ANSIWAVE   BBS | |             
  |         |      | |                | |             
  |:_____:  |      | |     Enjoy      | |             
  |    ==   |      | :   your stay    : |             
  |       O |      :  '--------------'  :             
  |       o |      :'---...______...---'              
  |       o |-._.-i___/'             \._              
  |'-.____o_|   '-.   '-...______...-'  `-._          
  :_________:      `.____________________   `-.___.-. 
                   .'.eeeeeeeeeeeeeeeeee.'.      :___:
                 .'.eeeeeeeeeeeeeeeeeeeeee.'.         
                :____________________________:
  """

proc init() =
  vfs.readUrl = "http://localhost:" & $port & "/" & server.dbFilename
  vfs.register()
  # create test db
  if os.fileExists(dbPath):
    os.removeFile(dbPath)
  var conn = db.open(dbPath)
  db.init(conn)
  db_sqlite.close(conn)
  var p1 = entities.Post(parent_id: 0, user_id: 0, body: ansiArt)
  p1.id = server.insertPost(s, p1)
  var
    alice = entities.User(username: "Alice", public_key: "stuff")
    bob = entities.User(username: "Bob", public_key: "asdf")
  alice.id = server.insertUser(s, alice)
  bob.id = server.insertUser(s, bob)
  var p2 = entities.Post(parent_id: p1.id, user_id: bob.id, body: "Hello, i'm bob")
  p2.id = server.insertPost(s, p2)
  var p3 = entities.Post(parent_id: p1.id, user_id: alice.id, body: "What's up")
  p3.id = server.insertPost(s, p3)

proc renderBBS*() =
  init()
  var
    root = client.query(c, server.ansiwavesDir.joinPath("1.ansiwave"))
    threads = client.queryPostChildren(c, server.dbFilename, 1)
  while true:
    let
      width = iw.terminalWidth()
      height = iw.terminalHeight()
    var
      tb = iw.newTerminalBuffer(width, height)
      screenLine = 0
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
        let lines = strutils.splitLines(post.body)
        iw.drawRect(tb, 0, screenLine, editorWidth, 1 + screenLine + lines.len, doubleStyle = false)
        screenLine += 1
        for line in lines:
          iw.write(tb, 1, screenLine, line)
          screenLine += 2
    # display and sleep
    iw.display(tb)
    os.sleep(sleepMsecs)

