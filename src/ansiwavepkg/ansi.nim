from strutils import nil
import tables
import streams
from wavecorepkg/ansi import nil

const
  defaultLineWidth = 80
  ESCAPE = '\x1B'
  CR     = '\x0D'
  LF     = '\x0A'
  COLOR_DEFAULT_TXT = "37"
  COLOR_DEFAULT_BG  = "40"
  cp437 = [
    "\x00", "☺", "☻", "♥", "♦", "♣", "♠", "•", "\b", "\t", "\n", "♂", "♀", "\r", "♫", "☼",
    "►", "◄", "↕", "‼", "¶", "§", "▬", "↨", "↑", "↓", "→", "\x1b", "∟", "↔", "▲", "▼",
    " ", "!", "\"", "#", "$", "%", "&", "'", "(", ")", "*", "+", ",", "-", ".", "/",
    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ":", ";", "<", "=", ">", "?",
    "@", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O",
    "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "[", "\\", "]", "^", "_",
    "`", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o",
    "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "{", "|", "}", "~", "⌂",
    "\u0080", "\u0081", "é", "â", "ä", "à", "å", "ç", "ê", "ë", "è", "ï", "î", "ì", "Ä", "Å",
    "É", "æ", "Æ", "ô", "ö", "ò", "û", "ù", "ÿ", "Ö", "Ü", "¢", "£", "¥", "₧", "ƒ",
    "á", "í", "ó", "ú", "ñ", "Ñ", "ª", "º", "¿", "⌐", "¬", "½", "¼", "¡", "«", "»",
    "░", "▒", "▓", "│", "┤", "╡", "╢", "╖", "╕", "╣", "║", "╗", "╝", "╜", "╛", "┐",
    "└", "┴", "┬", "├", "─", "┼", "╞", "╟", "╚", "╔", "╩", "╦", "╠", "═", "╬", "╧",
    "╨", "╤", "╥", "╙", "╘", "╒", "╓", "╫", "╪", "┘", "┌", "█", "▄", "▌", "▐", "▀",
    "α", "ß", "Γ", "π", "Σ", "σ", "µ", "τ", "Φ", "Θ", "Ω", "δ", "∞", "φ", "ε", "∩",
    "≡", "±", "≥", "≤", "⌠", "⌡", "÷", "≈", "°", "∙", "·", "√", "ⁿ", "²", "■", "\u00a0",
  ]

type
  Brush = object
    bold, faint, italic, underline, blink, inverse, conceal, strikethrough: bool
    colorTxt: string
    colorBg: string

proc initBrush(): Brush =
  Brush(colorBg: COLOR_DEFAULT_BG)

proc toEsc(brush: Brush, prevBrush: Brush): string =
  var parts: seq[string]

  let features = [
    (current: brush.bold,          previous: prevBrush.bold,          on: "1", off: "22"),
    (current: brush.faint,         previous: prevBrush.faint,         on: "2", off: "22"),
    (current: brush.italic,        previous: prevBrush.italic,        on: "3", off: "23"),
    (current: brush.underline,     previous: prevBrush.underline,     on: "4", off: "24"),
    (current: brush.blink,         previous: prevBrush.blink,         on: "5", off: "25"),
    (current: brush.inverse,       previous: prevBrush.inverse,       on: "7", off: "27"),
    (current: brush.conceal,       previous: prevBrush.conceal,       on: "8", off: "28"),
    (current: brush.strikethrough, previous: prevBrush.strikethrough, on: "9", off: "29"),
  ]

  for feature in features:
    if feature.current and not feature.previous:
      parts.add(feature.on)
    elif not feature.current and feature.previous:
      parts.add(feature.off)

  if brush.colorBg.len > 0 and brush.colorBg != prevBrush.colorBg:
    parts.add(brush.colorBg)

  if brush.colorTxt.len > 0 and brush.colorTxt != prevBrush.colorTxt:
    parts.add(brush.colorTxt)

  if parts.len > 0:
    return "\x1B[" & strutils.join(parts, ";") & "m"

proc parseParams*(code: string): seq[int] =
  assert code[0] == '['
  let parts = strutils.split(code[1 ..< code.len], ";")
  for part in parts:
    if part == "":
      continue
    let num = strutils.parseInt(part)
    result.add(num)

proc highColor(arCodes: seq[int]): (string, int) =
  let nCodes = arCodes.len

  func fnKosher(i: int): bool =
    (i >= 0) and (i <= 255)

  if nCodes >= 3:
    case arCodes[1]:
    of 5:
      if fnKosher(arCodes[2]):
        return (
          strutils.format("$1;$1;$1", arCodes[0], arCodes[1], arCodes[2]),
          2
        )
    of 2:
      if nCodes >= 5:
        if fnKosher(arCodes[2]) and fnKosher(arCodes[3]) and fnKosher(arCodes[4]):
          return (
            strutils.format("$1;$1;$1;$1;$1", arCodes[0], arCodes[1], arCodes[2], arCodes[3], arCodes[4]),
            4
          )
    else:
      discard

  return ("", 0)

proc merge(brush: var Brush, params: seq[int]) =
  var i = -1
  while i < params.len - 1:
    i = i + 1
    let param = params[i]
    case param:
    # reset
    of 0:
      brush = initBrush()

    # bold
    of 1:
      brush.bold = true
    of 21:
      brush.bold = false
    of 22:
      brush.bold = false
      brush.faint = false

    # faint
    of 2:
      brush.faint = true

    # italic
    of 3:
      brush.italic = true
    of 23:
      brush.italic = false

    # underline
    of 4:
      brush.underline = true
    of 24:
      brush.underline = false

    # blink
    of 5, 6:
      brush.blink = true
    of 25:
      brush.blink = false

    # inverse
    of 7:
      brush.inverse = true
    of 27:
      brush.inverse = false

    # conceal
    of 8:
      brush.conceal = true
    of 28:
      brush.conceal = false

    # strikethrough
    of 9:
      brush.strikethrough = true
    of 29:
      brush.strikethrough = false

    # default fg
    of 39:
      brush.colorTxt = COLOR_DEFAULT_TXT

    # default bg
    of 49:
      brush.colorBg = COLOR_DEFAULT_BG

    # high color fg
    # high color bg
    of 38, 48:
      let (szColor, nAdvance) = highColor(params[i ..< params.len])

      if nAdvance > 0:
        case param:
        of 38:
          brush.colorTxt = szColor
        of 48:
          brush.colorBg = szColor
        else:
          raise newException(Exception, "Invalid")

        i = i + nAdvance
        continue
      else:
        raise newException(Exception, "Invalid")
    else:
      # classic fg
      if param >= 30 and param <= 37:
        brush.colorTxt = $param
      # classic bg
      elif param >= 40 and param <= 47:
        brush.colorBg = $param
      else:
        raise newException(Exception, "Unknown param: " & $param)

type
  Pos = tuple[row: int, col: int]
  Val = tuple[utf8: string, brush: Brush]

proc incClamp(pos: var Pos, x: int, y: int, lineWidth: int) =
  let
    newRow = pos.row + y
    newCol = pos.col + x
  if newRow >= 0:
    pos.row = newRow
  if newCol >= 0 and newCol < lineWidth:
    pos.col = newCol

proc ansiToUtf8*(content: string, lineWidth: int = defaultLineWidth): OrderedTable[Pos, Val] =
  var
    isEscape = false
    curCode = ""
    curPos: Pos = (row: 0, col: 0)
    savedPos: Pos = (row: 0, col: 0)
    brush = initBrush()

  for ch in content:
    case ch:
    of CR:
      continue
    of ESCAPE:
      isEscape = true
      curCode = ""
    else:
      if isEscape:
        case ch:
        of ansi.codeTerminators:
          let params = parseParams(curCode)
          isEscape = false
          case ch:
          of 'm':
            merge(brush, params)
          of 'A': # up
            let amount = if params.len == 0: 1 else: params[0]
            incClamp(curPos, 0, -amount, lineWidth)
          of 'B': # down
            let amount = if params.len == 0: 1 else: params[0]
            incClamp(curPos, 0, amount, lineWidth)
          of 'C': # forward
            let amount = if params.len == 0: 1 else: params[0]
            incClamp(curPos, amount, 0, lineWidth)
          of 'D': # back
            let amount = if params.len == 0: 1 else: params[0]
            incClamp(curPos, -amount, 0, lineWidth)
          of 'H', 'f': # to x, y
            curPos.row = params[0]
            curPos.col = params[1]
          of 's': # save cursor pos
            savedPos = curPos
          of 'u': # restore cursor pos
            curPos = savedPos
          else:
            continue
          continue
        of '\1' .. '\31':
          continue
        else:
          curCode = curCode & ch
    if not isEscape:
      if ch == LF:
        result[curPos] = (" ", brush)
        curPos.row = curPos.row + 1
        curPos.col = 0
      elif ch != '\b':
        var rune = cp437[ch.int]
        if strutils.contains("\x00\r\n\t", rune):
          rune = " "
        result[curPos] = (rune, brush)
        if curPos.col + 1 < lineWidth:
          curPos.col = curPos.col + 1
        else:
          curPos.row = curPos.row + 1
          curPos.col = 0

  proc cmpPos(a, b: (Pos, Val)): int =
    let row = cmp(a[0].row, b[0].row)
    if row != 0:
      return row
    let col = cmp(a[0].col, b[0].col)
    if col != 0:
      return col
    return 0

  result.sort(cmpPos)

proc clear(file: File | StringStream) =
  file.write("\x1B[0m")

proc newLine(file: File | StringStream) =
  file.clear
  file.write('\n')
  file.clear

proc fillRestOfLine(file: File | StringStream, curCol: var int, lineWidth: int) =
  while curCol < lineWidth:
    file.write(' ')
    curCol = curCol + 1

proc write*(file: File | StringStream, grid: OrderedTable[Pos, Val], lineWidth: int = defaultLineWidth) =
  var
    curRow = 0
    curCol = 0
    curBrush = Brush()

  file.clear
  for pos, item in grid.pairs:
    while curRow != pos.row:
      file.fillRestOfLine(curCol, lineWidth)
      file.newLine
      file.write(toEsc(initBrush(), Brush()))
      curRow = curRow + 1
      curCol = 0
    while curCol != pos.col:
      file.write(' ')
      curCol = curCol + 1
    curRow = pos.row
    curCol = pos.col + 1
    if curBrush != item.brush:
      file.write(toEsc(item.brush, curBrush))
      curBrush = item.brush
    file.write(item.utf8)
  file.fillRestOfLine(curCol, lineWidth)
  file.newLine
