from illwill as iw import `[]`, `[]=`
from ansi import nil
from strutils import nil
from sequtils import nil
import unicode
import sets

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
  var
    i = params.len - 1
    existingParams: HashSet[int]
    uniqueParams = params.toHashSet
  # don't dedupe if we are setting RGB colors
  if intersection(uniqueParams, [38, 48].toHashSet).len > 0:
    return
  while i > 0:
    let param = params[i]
    # if it's a clear, ignore all prior params
    if param == 0:
      params = params[i ..< params.len]
      break
    if param in existingParams:
      # if the param already exists, no need to include it again
      params.delete(i)
      i.dec
    else:
      existingParams.incl(param)
      # if the param is a color, remove all prior colors of the same kind because it's redundant
      if param >= 30 and param <= 37:
        let prevParams = sequtils.filter(params[0 ..< i], proc (x: int): bool = not (x >= 30 and x <= 37))
        params = prevParams & params[i ..< params.len]
        i = prevParams.len - 1
      elif param >= 40 and param <= 47:
        let prevParams = sequtils.filter(params[0 ..< i], proc (x: int): bool = not (x >= 40 and x <= 47))
        params = prevParams & params[i ..< params.len]
        i = prevParams.len - 1
      else:
        i.dec

proc applyCode(tb: var iw.TerminalBuffer, code: string) =
  let trimmed = code[1 ..< code.len - 1]
  let params = ansi.parseParams(trimmed)
  var bright = false
  for param in params:
    if param == 0:
      iw.setBackgroundColor(tb, iw.bgNone)
      iw.setForegroundColor(tb, iw.fgNone)
      iw.setStyle(tb, {})
    elif param >= 1 and param <= 9:
      if param == 1:
        bright = true
      var style = iw.getStyle(tb)
      style.incl(iw.Style(param))
      iw.setStyle(tb, style)
    elif param >= 30 and param <= 37:
      iw.setForegroundColor(tb, iw.ForegroundColor(param), bright)
    elif param >= 40 and param <= 47:
      iw.setBackgroundColor(tb, iw.BackgroundColor(param))

proc write*(tb: var iw.TerminalBuffer, x, y: Natural, s: string) =
  var currX = x
  var codes: seq[string]
  for ch in runes(s):
    if parseCode(codes, ch):
      continue
    for code in codes:
      applyCode(tb, code)
    var c = iw.TerminalChar(ch: ch, fg: iw.getForegroundColor(tb), bg: iw.getBackgroundColor(tb),
                            style: iw.getStyle(tb))
    tb[currX, y] = c
    inc(currX)
    codes = @[]
  for code in codes:
    applyCode(tb, code)
  iw.setCursorXPos(tb, currX)
  iw.setCursorYPos(tb, y)

proc stripCodes*(line: seq[Rune]): seq[Rune] =
  var codes: seq[string]
  for ch in line:
    if parseCode(codes, ch):
      continue
    result.add(ch)

proc stripCodes*(line: string): string =
  $stripCodes(line.toRunes)

proc stripCodesIfCommand*(line: ref string): string =
  var
    codes: seq[string]
    foundFirstValidChar = false
  for ch in runes(line[]):
    if parseCode(codes, ch):
      continue
    if not foundFirstValidChar and ch.toUTF8[0] != '/':
      return ""
    else:
      foundFirstValidChar = true
      result &= $ch

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
