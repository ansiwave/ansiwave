from illwave as iw import `[]`, `[]=`, `==`
import unicode, json, tables
from nimwave import nil
from strutils import nil

const height* = 3

type
  Button = object
    cb: proc ()
    focused: bool

proc render*(ctx: var nimwave.Context, input: tuple[key: iw.Key, codepoint: uint32], leftButtons: openArray[(string, proc())], middleLines: openArray[string], rightButtons: openArray[(string, proc())], focusIndex: var int) =
  var newContext = nimwave.slice(ctx, 0, 0, iw.width(ctx.tb), height)
  iw.fill(newContext.tb, 0, 0, iw.width(newContext.tb), iw.height(newContext.tb))

  var lineY = 0
  for line in middleLines:
    var s = ""
    for ch in line:
      # dumb/primitive way of filtering out invalid chars in error message
      if ch in {'a'..'z', 'A'..'Z', '0'..'9', ' ', '\'', '(', ')', '<', '>', ','}:
        s &= ch
        if s.len == iw.width(newContext.tb):
          break
    iw.write(newContext.tb, max(0, int(iw.width(newContext.tb).float / 2 - s.len / 2)), lineY, s)
    lineY += 1

  let buttonCount = leftButtons.len + rightButtons.len
  case input.key:
  of iw.Key.Right:
    if focusIndex < 0 and abs(focusIndex) < buttonCount:
      focusIndex -= 1
  of iw.Key.Left:
    if focusIndex < -1:
      focusIndex += 1
  else:
    discard

  var
    buttons: Table[string, Button]
    leftButtonsWidth = 0
    rightButtonsWidth = 0
  var buttonFocus = -1
  for (text, cb) in leftButtons:
    buttons[text] = Button(cb: cb, focused: buttonFocus == focusIndex)
    buttonFocus -= 1
    leftButtonsWidth += text.runeLen + 2
  for (text, cb) in rightButtons:
    buttons[text] = Button(cb: cb, focused: buttonFocus == focusIndex)
    buttonFocus -= 1
    rightButtonsWidth += text.runeLen + 2

  proc navButton(ctx: var nimwave.Context, id: string, opts: JsonNode, children: seq[JsonNode]) =
    let
      text = opts["text"].str
      focused = buttons[text].focused
    ctx = nimwave.slice(ctx, 0, 0, text.runeLen + 2, iw.height(ctx.tb))
    if input.key == iw.Key.Mouse:
      let info = iw.getMouse()
      if info.action == iw.MouseButtonAction.mbaPressed and iw.contains(ctx.tb, info):
        buttons[text].cb()
    elif input.key == iw.Key.Enter and focused:
      buttons[text].cb()
    nimwave.render(ctx, %* ["hbox", {"border": if focused: "double" else: "single"}, text])

  var leftBox = %* ["hbox"]
  for (text, _) in leftButtons:
    leftBox.add(%* ["nav-button", {"text": text}])
  var rightBox = %* ["hbox"]
  for (text, _) in rightButtons:
    rightBox.add(%* ["nav-button", {"text": text}])

  let
    spacerWidth = max(0, iw.width(newContext.tb) - leftButtonsWidth - rightButtonsWidth)
    spacer = strutils.repeat(' ', spacerWidth)

  newContext.components["nav-button"] = navButton
  nimwave.render(newContext, %* ["hbox", leftBox, spacer, rightBox])

