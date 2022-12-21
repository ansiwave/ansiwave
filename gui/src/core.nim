import paranim/opengl
import paranim/gl, paranim/gl/entities
from paranim/glm import vec4
from paratext/gl/text import nil
from paratext import nil
import deques
from wavecorepkg/paths import nil
from strutils import nil
import tables, unicode

from illwave as iw import `[]`, `[]=`, `==`

from ansiwavepkg/bbs import nil
from ansiwavepkg/ui/context import nil

from wavecorepkg/client import nil

from nimwave/gui import nil
from nimwave/tui import nil

const
  monoFontRaw = staticRead("assets/3270-Regular.ttf")
  charCount = gui.codepointToGlyph.len
  blockCharIndex = gui.codepointToGlyph["█".toRunes[0].int32]
  bgColor = glm.vec4(0f/255f, 16f/255f, 64f/255f, 0.95f)
  textColor = glm.vec4(230f/255f, 235f/255f, 1f, 1f)

let
  monoFont = paratext.initFont(ttf = monoFontRaw, fontHeight = 80,
                               ranges = gui.charRanges,
                               bitmapWidth = 2048, bitmapHeight = 2048, charCount = charCount)
  blockWidth = monoFont.chars[blockCharIndex].xadvance

type
  Game* = object of RootGame
    deltaTime*: float
    totalTime*: float
    windowWidth*: int32
    windowHeight*: int32
    worldWidth*: int32
    worldHeight*: int32
    mouseX*: float
    mouseY*: float

var
  clnt: client.Client
  session*: bbs.BbsSession
  baseEntity: text.UncompiledTextEntity
  textEntity: gui.NimwaveTextEntity
  fontMultiplier* = 1/4
  keyQueue: Deque[(iw.Key, iw.MouseInfo)]
  charQueue: Deque[uint32]
  pixelDensity*: float
  failAle*: bool

proc fontWidth*(): float =
  blockWidth * fontMultiplier

proc fontHeight*(): float =
  monoFont.height * fontMultiplier

proc onKeyPress*(key: iw.Key) =
  keyQueue.addLast((key, context.mouseInfo))

proc onKeyRelease*(key: iw.Key) =
  discard

proc onChar*(codepoint: uint32) =
  charQueue.addLast(codepoint)

proc onMouseClick*(button: iw.MouseButton, action: iw.MouseButtonAction, xpos: float, ypos: float) =
  context.mouseInfo.button = button
  context.mouseInfo.action = action
  context.mouseInfo.x = int(xpos / fontWidth() - 0.25)
  context.mouseInfo.y = int(ypos / fontHeight() - 0.25)
  keyQueue.addLast((iw.Key.Mouse, context.mouseInfo))

proc onMouseMove*(xpos: float, ypos: float) =
  context.mouseInfo.x = int(xpos / fontWidth() - 0.25)
  context.mouseInfo.y = int(ypos / fontHeight() - 0.25)
  if context.mouseInfo.action == iw.MouseButtonAction.mbaPressed and bbs.isEditor(session):
    keyQueue.addLast((iw.Key.Mouse, context.mouseInfo))

proc onWindowResize*(windowWidth: int, windowHeight: int) =
  discard

proc onScroll*(xoffset: float, yoffset: float) =
  # treat scrolling up/down the same as arrow up/down
  if yoffset < 0:
    keyQueue.addLast((iw.Key.Down, context.mouseInfo))
  elif yoffset > 0:
    keyQueue.addLast((iw.Key.Up, context.mouseInfo))

proc init*(game: var Game) =
  clnt = client.initClient(paths.address, paths.postAddress)
  client.start(clnt)

  bbs.init()

  var hash: Table[string, string]
  if "board" notin hash:
    hash["board"] = paths.defaultBoard

  # this must be done before the gl stuff
  # that way, it will initialize even if the gl stuff fails
  session = bbs.initBbsSession(clnt, hash)

  doAssert glInit()

  glEnable(GL_BLEND)
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
  glDisable(GL_CULL_FACE)
  glDisable(GL_DEPTH_TEST)

  baseEntity = text.initTextEntity(monoFont)
  textEntity = compile(game, gui.initInstancedEntity(baseEntity, monoFont))

proc tick*(game: Game): bool =
  glClearColor(bgColor.arr[0], bgColor.arr[1], bgColor.arr[2], bgColor.arr[3])
  glClear(GL_COLOR_BUFFER_BIT)
  glViewport(0, 0, GLsizei(game.windowWidth), GLsizei(game.windowHeight))

  var finishedLoading = false
  let
    fontWidth = fontWidth()
    fontHeight = fontHeight()

  let
    termWidth = int(game.windowWidth.float / fontWidth)
    termHeight = int(game.windowHeight.float / fontHeight)
    vWidth = termWidth.float * fontWidth
    vHeight = termHeight.float * fontHeight

  var tb: iw.TerminalBuffer

  if failAle:
    tb = iw.initTerminalBuffer(termWidth, termHeight)
    const lines = strutils.splitLines(staticRead("assets/failale.ansiwave"))
    var y = 0
    for line in lines:
      tui.write(tb, 0, y, line)
      y += 1
  else:
    var rendered = false
    while keyQueue.len > 0 or charQueue.len > 0:
      let
        (key, mouseInfo) = if keyQueue.len > 0: keyQueue.popFirst else: (iw.Key.None, context.mouseInfo)
        ch = if charQueue.len > 0 and key == iw.Key.None: charQueue.popFirst else: 0
      context.mouseInfo = mouseInfo
      tb = bbs.tick(session, clnt, termWidth, termHeight, (key, ch), finishedLoading)
      rendered = true
    if not rendered:
      tb = bbs.tick(session, clnt, termWidth, termHeight, (iw.Key.None, 0'u32), finishedLoading)

  var e = gl.copy(textEntity)
  gui.updateUniforms(e, 0, 0, false)
  for y in 0 ..< termHeight:
    var line: seq[iw.TerminalChar]
    for x in 0 ..< termWidth:
      line.add(tb[x, y])
    discard gui.addLine(e, baseEntity, monoFont, gui.codepointToGlyph, textColor, line)
  e.project(vWidth, vHeight)
  e.translate(0f, 0f)
  e.scale(fontMultiplier, fontMultiplier)
  render(game, e)

  return finishedLoading

