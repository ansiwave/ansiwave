from illwave as iw import `[]`, `[]=`, `==`
import unicode
from nimwave as nw import nil
from ./context import nil

const height* = 3

type
  NavButton = ref object of nw.Node
    text: string
    focused: bool
    input: tuple[key: iw.Key, codepoint: uint32]
    cb: proc ()
  Spacer = ref object of nw.Node
    width: int

method render*(node: NavButton, ctx: var context.Context) =
  ctx = nw.slice(ctx, 0, 0, node.text.runeLen + 2, iw.height(ctx.tb))
  if node.input.key == iw.Key.Mouse:
    let info = context.mouseInfo
    if info.action == iw.MouseButtonAction.mbaPressed and iw.contains(ctx.tb, info):
      node.cb()
  elif node.input.key == iw.Key.Enter and node.focused:
    node.cb()
  context.render(
    nw.Box(
      direction: nw.Direction.Horizontal,
      border: if node.focused: nw.Border.Double else: nw.Border.Single,
      children: nw.seq(nw.Text(str: node.text)),
    ),
    ctx
  )

method render*(node: Spacer, ctx: var context.Context) =
  ctx = nw.slice(ctx, 0, 0, node.width, iw.height(ctx.tb))

proc render*(ctx: var context.Context, input: tuple[key: iw.Key, codepoint: uint32], leftButtons: openArray[(string, proc())], middleLines: openArray[string], rightButtons: openArray[(string, proc())], focusIndex: ref int) =
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
    if focusIndex[] < 0 and abs(focusIndex[]) < buttonCount:
      focusIndex[] -= 1
  of iw.Key.Left:
    if focusIndex[] < -1:
      focusIndex[] += 1
  else:
    discard

  var
    leftButtonsWidth = 0
    rightButtonsWidth = 0
    buttonFocus = -1

  var leftBoxChildren: seq[nw.Node]
  for (text, cb) in leftButtons:
    leftBoxChildren.add(NavButton(text: text, focused: buttonFocus == focusIndex[], input: input, cb: cb))
    buttonFocus -= 1
    leftButtonsWidth += text.runeLen + 2
  let leftBox = nw.Box(
    direction: nw.Direction.Horizontal,
    children: leftBoxChildren,
  )
  var rightBoxChildren: seq[nw.Node]
  for (text, cb) in rightButtons:
    rightBoxChildren.add(NavButton(text: text, focused: buttonFocus == focusIndex[], input: input, cb: cb))
    buttonFocus -= 1
    rightButtonsWidth += text.runeLen + 2
  let rightBox = nw.Box(
    direction: nw.Direction.Horizontal,
    children: rightBoxChildren,
  )

  let spacerWidth = max(0, iw.width(ctx.tb) - leftButtonsWidth - rightButtonsWidth)

  context.render(
    nw.Box(
      direction: nw.Direction.Horizontal,
      children: nw.seq(
        leftBox,
        Spacer(width: spacerWidth),
        rightBox,
      ),
    ),
    ctx
  )

