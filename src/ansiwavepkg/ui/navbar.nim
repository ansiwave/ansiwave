from illwave as iw import `[]`, `[]=`, `==`
import unicode, json, tables
from nimwave import nil
from strutils import nil
from ./context import nil

const height* = 3

type
  Button = object
    cb: proc ()
    focused: bool

proc render*(ctx: var context.Context, input: tuple[key: iw.Key, codepoint: uint32], leftButtons: openArray[(string, proc())], middleLines: openArray[string], rightButtons: openArray[(string, proc())], focusIndex: var int) =
  iw.fill(ctx.tb, 0, 0, iw.width(ctx.tb), iw.height(ctx.tb))

  var lineY = 0
  for line in middleLines:
    var s = ""
    for ch in line:
      # dumb/primitive way of filtering out invalid chars in error message
      if ch in {'a'..'z', 'A'..'Z', '0'..'9', ' ', '\'', '(', ')', '<', '>', ','}:
        s &= ch
        if s.len == iw.width(ctx.tb):
          break
    iw.write(ctx.tb, max(0, int(iw.width(ctx.tb).float / 2 - s.len / 2)), lineY, s)
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

  proc navButton(ctx: var context.Context, data: ref context.State, node: JsonNode, children: seq[JsonNode]) =
    let
      text = node["text"].str
      focused = buttons[text].focused
    ctx = nimwave.slice(ctx, 0, 0, text.runeLen + 2, iw.height(ctx.tb))
    if input.key == iw.Key.Mouse:
      let info = iw.getMouse()
      if info.action == iw.MouseButtonAction.mbaPressed and iw.contains(ctx.tb, info):
        buttons[text].cb()
    elif input.key == iw.Key.Enter and focused:
      buttons[text].cb()
    nimwave.render(ctx, %* {"type": "hbox", "border": if focused: "double" else: "single", "children": [text]})
  ctx.components["nav-button"] = navButton

  var leftBoxChildren = %* []
  for (text, _) in leftButtons:
    leftBoxChildren.add(%* {"type": "nav-button", "text": text})
  var leftBox = %* {"type": "hbox", "children": leftBoxChildren}
  var rightBoxChildren = %* []
  for (text, _) in rightButtons:
    rightBoxChildren.add(%* {"type": "nav-button", "text": text})
  var rightBox = %* {"type": "hbox", "children": rightBoxChildren}

  let
    spacerWidth = max(0, iw.width(ctx.tb) - leftButtonsWidth - rightButtonsWidth)
    spacer = strutils.repeat(' ', spacerWidth)
  proc spacerView(ctx: var context.Context, data: ref context.State, node: JsonNode, children: seq[JsonNode]) =
    ctx = nimwave.slice(ctx, 0, 0, spacer.runeLen, iw.height(ctx.tb))
  ctx.components["spacer"] = spacerView

  nimwave.render(ctx, %* [{"type": "hbox", "children": [leftBox, {"type": "spacer"}, rightBox]}])

