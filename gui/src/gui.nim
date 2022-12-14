import paranim/glfw
from core import nil
import tables
import bitops
from ansiwavepkg/ui/editor import nil
from strutils import nil
from nimwave/gui import nil

var
  game: core.Game
  window: GLFWWindow

proc keyCallback(window: GLFWWindow, key: int32, scancode: int32, action: int32, mods: int32) {.cdecl.} =
  if key < 0:
    return
  let keys =
    if 0 != bitand(mods, GLFW_MOD_CONTROL):
      gui.glfwToIllwaveCtrlKey
    else:
      gui.glfwToIllwaveKey
  if keys.hasKey(key):
    let iwKey = keys[key]
    if action in {GLFW_PRESS, GLFW_REPEAT}:
      core.onKeyPress(iwKey)
    elif action == GLFW_RELEASE:
      core.onKeyRelease(iwKey)

proc charCallback(window: GLFWWindow, codepoint: uint32) {.cdecl.} =
  core.onChar(codepoint)

proc updateCoords(xpos: var float64, ypos: var float64) =
  let mult = core.pixelDensity
  xpos = xpos * mult
  ypos = ypos * mult

proc cursorPosCallback(window: GLFWWindow, xpos: float64, ypos: float64) {.cdecl.} =
  var
    mouseX = xpos
    mouseY = ypos
  updateCoords(mouseX, mouseY)
  core.onMouseMove(mouseX, mouseY)

proc mouseButtonCallback(window: GLFWWindow, button: int32, action: int32, mods: int32) {.cdecl.} =
  if gui.glfwToIllwaveMouseButton.hasKey(button) and gui.glfwToIllwaveMouseAction.hasKey(action):
    var
      xpos: float64
      ypos: float64
    getCursorPos(window, xpos.addr, ypos.addr)
    updateCoords(xpos, ypos)
    core.onMouseClick(gui.glfwToIllwaveMouseButton[button], gui.glfwToIllwaveMouseAction[action], xpos, ypos)

proc frameSizeCallback(window: GLFWWindow, width: int32, height: int32) {.cdecl.} =
  game.windowWidth = width
  game.windowHeight = height
  core.onWindowResize(game.windowWidth, game.windowHeight)

proc scrollCallback(window: GLFWWindow, xoffset: float64, yoffset: float64) {.cdecl.} =
  core.onScroll(xoffset, yoffset)

proc main*() =
  doAssert glfwInit()

  glfwWindowHint(GLFWContextVersionMajor, 3)
  glfwWindowHint(GLFWContextVersionMinor, 3)
  glfwWindowHint(GLFWOpenglForwardCompat, GLFW_TRUE) # Used for Mac
  glfwWindowHint(GLFWOpenglProfile, GLFW_OPENGL_CORE_PROFILE)
  glfwWindowHint(GLFWResizable, GLFW_TRUE)
  glfwWindowHint(GLFWTransparentFramebuffer, GLFW_TRUE)

  window = glfwCreateWindow(1024, 768, "ANSIWAVE")
  if window == nil:
    quit(-1)

  window.makeContextCurrent()
  glfwSwapInterval(1)

  discard window.setKeyCallback(keyCallback)
  discard window.setCharCallback(charCallback)
  discard window.setMouseButtonCallback(mouseButtonCallback)
  discard window.setCursorPosCallback(cursorPosCallback)
  discard window.setFramebufferSizeCallback(frameSizeCallback)
  discard window.setScrollCallback(scrollCallback)

  var width, height: int32
  window.getFramebufferSize(width.addr, height.addr)

  var windowWidth, windowHeight: int32
  window.getWindowSize(windowWidth.addr, windowHeight.addr)

  window.frameSizeCallback(width, height)

  editor.copyCallback =
    proc (lines: seq[string]) =
      let s = strutils.join(lines, "\n")
      window.setClipboardString(s)

  core.init(game)

  core.pixelDensity = max(1f, width / windowWidth)
  core.fontMultiplier *= core.pixelDensity

  game.totalTime = glfwGetTime()

  while not window.windowShouldClose:
    try:
      let ts = glfwGetTime()
      game.deltaTime = ts - game.totalTime
      game.totalTime = ts
      let canSleep = core.tick(game)
      window.swapBuffers()
      if canSleep:
        glfwWaitEvents()
      else:
        glfwPollEvents()
    except Exception as ex:
      stderr.writeLine(ex.msg)
      stderr.writeLine(getStackTrace(ex))
      core.failAle = true

  window.destroyWindow()
  glfwTerminate()

