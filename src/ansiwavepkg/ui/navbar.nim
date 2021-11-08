from ../illwill as iw import `[]`, `[]=`
from ../constants import nil
from ./editor import nil
import unicode

const height* = 3

proc renderButton(tb: var iw.TerminalBuffer, text: string, x: int, y: int, key: iw.Key, cb: proc (), shortcut: tuple[key: set[iw.Key], hint: string] = ({}, "")): int =
  result = x + text.runeLen + 1
  iw.drawRect(tb, x, y, result, y + height - 1, doubleStyle = false)
  iw.write(tb, x + 1, y + 1, text)
  if key == iw.Key.Mouse:
    let info = iw.getMouse()
    if info.button == iw.MouseButton.mbLeft and info.action == iw.MouseButtonAction.mbaPressed:
      if info.x >= x and
          info.x < result and
          info.y == y:
        cb()
  elif key in shortcut.key:
    cb()
  result += 1

proc render*(tb: var iw.TerminalBuffer, pageX: int, pageY: int, input: tuple[key: iw.Key, codepoint: uint32]) =
  iw.fill(tb, pageX, pageY, pageX + constants.editorWidth + 1, pageY + height - 1)
  var x = pageX
  x = renderButton(tb, " ← ", x, pageY, input.key, proc () = discard)
  x = renderButton(tb, " → ", x, pageY, input.key, proc () = discard)
  let sendStr = " Send "
  discard renderButton(tb, sendStr, constants.editorWidth - sendStr.runeLen, pageY, input.key, proc () = discard)

