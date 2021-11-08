from ../illwill as iw import `[]`, `[]=`
from ../constants import nil
from ./editor import nil
import unicode

const height* = 3

proc renderButton(tb: var iw.TerminalBuffer, text: string, x: int, y: int, key: iw.Key, cb: proc (), shortcut: tuple[key: set[iw.Key], hint: string] = ({}, "")): int =
  result = x + text.runeLen + 1
  let endY = y + height - 1
  iw.drawRect(tb, x, y, result, endY, doubleStyle = false)
  iw.write(tb, x + 1, y + 1, text)
  if key == iw.Key.Mouse:
    let info = iw.getMouse()
    if info.button == iw.MouseButton.mbLeft and info.action == iw.MouseButtonAction.mbaPressed:
      if info.x >= x and
          info.x < result and
          info.y >= y and
          info.y < endY:
        cb()
  elif key in shortcut.key:
    cb()
  result += 1

proc render*(tb: var iw.TerminalBuffer, pageX: int, pageY: int, input: tuple[key: iw.Key, codepoint: uint32], leftButtons: openArray[(string, proc())], rightButtonText: string, rightButtonAction: proc ()) =
  iw.fill(tb, pageX, pageY, pageX + constants.editorWidth + 1, pageY + height - 1)
  var x = pageX
  for (text, cb) in leftButtons:
    x = renderButton(tb, text, x, pageY, input.key, cb)
  if rightButtonText != "":
    discard renderButton(tb, rightButtonText, max(x, constants.editorWidth - rightButtonText.runeLen), pageY, input.key, rightButtonAction)

