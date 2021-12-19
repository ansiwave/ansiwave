from ./illwill as iw import `[]`, `[]=`
from ./ansi import nil
from strutils import nil
from sequtils import nil
import unicode
import sets
from ./kdtree import nil

proc parseCode(codes: var seq[string], ch: Rune): bool =
  proc terminated(s: string): bool =
    if s.len > 0:
      let lastChar = s[s.len - 1]
      return ansi.codeTerminators.contains(lastChar)
    else:
      return false
  let s = $ch
  if s == "\e":
    codes.add(s)
    return true
  elif codes.len > 0 and not codes[codes.len - 1].terminated:
    codes[codes.len - 1] &= s
    return true
  return false

proc dedupeParams(params: var seq[int]) =
  # partition the params so RGB values are grouped together.
  # for example, @[0,38,2,4,6,8,48,2,114,129,163]
  # turns into @[@[0], @[38,2,4,6,8], @[48,2,114,129,163]]
  var
    partitionedParams: seq[seq[int]]
    i = 0
  while i < params.len:
    let param = params[i]
    if param in {38, 48}:
      if i + 1 < params.len:
        let mode = params[i + 1]
        if mode == 5:
          if i + 2 < params.len:
            partitionedParams.add(params[i .. i+2])
            i += 3
            continue
        elif mode == 2:
          if i + 4 < params.len:
            partitionedParams.add(params[i .. i+4])
            i += 5
            continue
        # the values appear to be invalid so just stop trying to make sense of them
        break
    else:
      partitionedParams.add(@[param])
    i += 1
  # remove partitions that wouldn't affect rendering anyway
  i = partitionedParams.len - 1
  var existingParams: HashSet[int]
  while i >= 0:
    let param = partitionedParams[i][0]
    # if it's a clear, ignore all prior params
    if param == 0:
      partitionedParams = partitionedParams[i ..< partitionedParams.len]
      break
    elif param == 5:
      # remove blinking because it's annoying
      partitionedParams.delete(i)
    elif param in existingParams:
      # if the param already exists, no need to include it again
      partitionedParams.delete(i)
    else:
      existingParams.incl(param)
      # if the param is a color, add all other colors of the same type to existingParams
      # so they are removed (they would have no effect anyway)
      if param >= 30 and param <= 38:
        existingParams.incl([30, 31, 32, 33, 34, 35, 36, 37, 38].toHashSet)
      elif param >= 40 and param <= 48:
        existingParams.incl([40, 41, 42, 43, 44, 45, 46, 47, 48].toHashSet)
    i -= 1
  # flatten the partitions back into the params seq
  params = @[]
  for partition in partitionedParams:
    params.add(partition)

const colors = [
  ([0.0, 0.0, 0.0], (iw.fgBlack, iw.bgBlack)),
  ([255.0, 0.0, 0.0], (iw.fgRed, iw.bgRed)),
  ([0.0, 128.0, 0.0], (iw.fgGreen, iw.bgGreen)),
  ([255.0, 255.0, 0.0], (iw.fgYellow, iw.bgYellow)),
  ([0.0, 0.0, 255.0], (iw.fgBlue, iw.bgBlue)),
  ([255.0, 0.0, 255.0], (iw.fgMagenta, iw.bgMagenta)),
  ([0.0, 255.0, 255.0], (iw.fgCyan, iw.bgCyan)),
  ([255.0, 255.0, 255.0], (iw.fgWhite, iw.bgWhite)),
]
var tree = kdtree.newKdTree[(iw.ForegroundColor, iw.BackgroundColor)](colors)

proc applyCode(tb: var iw.TerminalBuffer, code: string) =
  let
    trimmed = code[1 ..< code.len - 1]
    params = ansi.parseParams(trimmed)
  var i = 0
  while i < params.len:
    let param = params[i]
    if param == 0:
      iw.setBackgroundColor(tb, iw.bgNone)
      iw.setForegroundColor(tb, iw.fgNone)
      iw.setStyle(tb, {})
    elif param >= 1 and param <= 9:
      var style = iw.getStyle(tb)
      style.incl(iw.Style(param))
      iw.setStyle(tb, style)
    elif param == 22:
      var style = iw.getStyle(tb)
      style.excl(iw.Style(1))
      style.excl(iw.Style(2))
      iw.setStyle(tb, style)
    elif param >= 30 and param <= 37:
      iw.setForegroundColor(tb, iw.ForegroundColor(param))
    elif param >= 40 and param <= 47:
      iw.setBackgroundColor(tb, iw.BackgroundColor(param))
    elif param == 38 or param == 48:
      if i + 1 < params.len:
        let mode = params[i + 1]
        # convert 256 colors to standard 8 terminal colors
        if mode == 5:
          if i + 2 < params.len:
            # TODO: correctly convert the 256 color value to one of the 8 terminal colors
            if param == 38:
              iw.setForegroundColor(tb, iw.fgNone)
            else:
              iw.setBackgroundColor(tb, iw.bgNone)
            i += 3
            continue
        # convert truecolor to standard 8 terminal colors
        elif mode == 2:
          if i + 4 < params.len:
            let
              r = params[i + 2].uint
              g = params[i + 3].uint
              b = params[i + 4].uint
              (pt, value, dist) = kdtree.nearestNeighbour(tree, [float(r), float(g), float(b)])
            if param == 38:
              iw.setForegroundColor(tb, value[0], (r, g, b))
            else:
              iw.setBackgroundColor(tb, value[1], (r, g, b))
            i += 5
            continue
        # the values appear to be invalid so just stop trying to make sense of them
        break
    i += 1

proc write*(tb: var iw.TerminalBuffer, x, y: int, s: string) =
  if y < 0 or y > iw.height(tb):
    return
  var currX = x
  var codes: seq[string]
  for ch in runes(s):
    if parseCode(codes, ch):
      continue
    for code in codes:
      applyCode(tb, code)
    var c = iw.TerminalChar(ch: ch, fg: iw.getForegroundColor(tb), bg: iw.getBackgroundColor(tb),
                            style: iw.getStyle(tb),
                            fgTruecolor: tb.currFgTruecolor, bgTruecolor: tb.currBgTruecolor)
    tb[currX, y] = c
    inc(currX)
    codes = @[]
  for code in codes:
    applyCode(tb, code)
  iw.setCursorXPos(tb, currX)
  iw.setCursorYPos(tb, y)

proc writeMaybe*(tb: var iw.TerminalBuffer, x, y: int, s: string) =
  try:
    write(tb, x, y, s)
  except Exception as ex:
    discard

proc stripCodes*(line: seq[Rune]): seq[Rune] =
  var codes: seq[string]
  for ch in line:
    if parseCode(codes, ch):
      continue
    result.add(ch)

proc stripCodes*(line: string): string =
  $stripCodes(line.toRunes)

proc stripCodesIfCommand*(line: string): string =
  var
    codes: seq[string]
    foundFirstValidChar = false
  for ch in runes(line):
    if parseCode(codes, ch):
      continue
    if not foundFirstValidChar and ch.toUTF8[0] != '/':
      return ""
    else:
      foundFirstValidChar = true
      result &= $ch

proc stripCodesIfCommand*(line: ref string): string =
  stripCodesIfCommand(line[])

proc dedupeCodes*(line: seq[Rune]): string =
  var
    codes: seq[string]
    lastParams: seq[int]
  proc addCodes(res: var string) =
    var params: seq[int]
    for code in codes:
      if code[1] == '[' and code[code.len - 1] == 'm':
        let
          trimmed = code[1 ..< code.len - 1]
          newParams = ansi.parseParams(trimmed)
        params &= newParams
      # this is some other kind of code that we should just preserve
      else:
        res &= code
    dedupeParams(params)
    if params.len > 0 and params != lastParams: # don't add params if they haven't changed
      res &= "\e[" & strutils.join(params, ";") & "m"
      lastParams = params
    codes = @[]
  for ch in line:
    if parseCode(codes, ch):
      continue
    elif codes.len > 0:
      addCodes(result)
    result &= $ch
  if codes.len > 0:
    addCodes(result)

proc dedupeCodes*(line: string): string =
  dedupeCodes(line.toRunes)

proc getRealX*(line: seq[Rune], x: int): int =
  result = 0
  var fakeX = 0
  var codes: seq[string]
  for ch in line:
    if parseCode(codes, ch):
      result.inc
      continue
    if fakeX == x:
      break
    result.inc
    fakeX.inc

proc getAllParams(line: seq[Rune]): seq[int] =
  var codes: seq[string]
  for ch in line:
    if parseCode(codes, ch):
      continue
  for code in codes:
    if code[1] == '[' and code[code.len - 1] == 'm':
      let trimmed = code[1 ..< code.len - 1]
      result &= ansi.parseParams(trimmed)

proc onlyHasClearParams*(line: string): bool =
  const clearSet = [0].toHashSet
  line.toRunes.getAllParams.toHashSet == clearSet

proc getParamsBeforeRealX*(line: seq[Rune], realX: int): seq[int] =
  result = getAllParams(line[0 ..< realX])
  dedupeParams(result)

proc getParamsBeforeRealX*(line: string, realX: int): seq[int] =
  getParamsBeforeRealX(line.toRunes, realX)

proc firstValidChar*(line: seq[Rune]): int =
  result = -1
  var realX = 0
  var codes: seq[string]
  for ch in line:
    if not parseCode(codes, ch):
      result = realX
      break
    realX.inc

proc deleteBefore*(line: var seq[Rune], count: int) =
  var x = 0
  while x < count:
    var firstChar = line.firstValidChar
    if firstChar == -1:
      break
    line.delete(firstChar)
    x.inc

proc firstValidCharAfter*(line: seq[Rune], count: int): int =
  result = -1
  var realX = 0
  var fakeX = 0
  var codes: seq[string]
  for ch in line:
    if not parseCode(codes, ch):
      if fakeX > count:
        result = realX
        break
      fakeX.inc
    realX.inc

proc deleteAfter*(line: var seq[Rune], count: int) =
  var x = 0
  var codes: seq[string]
  var firstCharAfter = 0
  while firstCharAfter != -1:
    firstCharAfter = line.firstValidCharAfter(count)
    if firstCharAfter == -1:
      break
    line.delete(firstCharAfter)
