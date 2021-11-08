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

proc renderTextField(tb: var iw.TerminalBuffer, text: string, x: int, y: int, width: int, key: iw.Key, cb: proc (), shortcut: tuple[key: set[iw.Key], hint: string] = ({}, "")) =
  let
    endX = x + width
    endY = y + height - 1
  iw.drawRect(tb, x, y, endX, endY, doubleStyle = false)
  iw.write(tb, x + 1, y + 1, text)
  if key == iw.Key.Mouse:
    let info = iw.getMouse()
    if info.button == iw.MouseButton.mbLeft and info.action == iw.MouseButtonAction.mbaPressed:
      if info.x >= x and
          info.x < endX and
          info.y >= y and
          info.y < endY:
        cb()
  elif key in shortcut.key:
    cb()

proc render*(tb: var iw.TerminalBuffer, pageX: int, pageY: int, input: tuple[key: iw.Key, codepoint: uint32], rightButtonText: string, rightButtonAction: proc (), showSearch: bool = true) =
  iw.fill(tb, pageX, pageY, pageX + constants.editorWidth + 1, pageY + height - 1)
  var x = pageX
  x = renderButton(tb, " ← ", x, pageY, input.key, proc () = discard)
  if rightButtonText != "":
    discard renderButton(tb, rightButtonText, constants.editorWidth - rightButtonText.runeLen, pageY, input.key, rightButtonAction)
  let rightButtonWidth =
    if rightButtonText != "":
      rightButtonText.runeLen + 2
    else:
      0
  if showSearch:
    let
      searchWidth = constants.editorWidth - x - rightButtonWidth + 1
      searchText = " Press / to search "
    renderTextField(tb, searchText, x, pageY, searchWidth, input.key, proc () = discard)

