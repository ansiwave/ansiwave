from illwill as iw import `[]`, `[]=`
from wavecorepkg/wavescript import nil
from strutils import format
from sequtils import nil
from ./codes import stripCodes
from unicode import nil
from paramidi import nil
from ./midi import nil
from times import nil
from ./sound import nil
from os import nil
from ./constants import nil
from json import nil

type
  RefStrings* = ref seq[ref string]

proc splitLines*(text: string): RefStrings =
  new result
  var row = 0
  for line in strutils.splitLines(text):
    var s: ref string
    new s
    s[] = codes.dedupeCodes(line)
    result[].add(s)
    # make sure the line is UTF-8
    let col = unicode.validateUtf8(line)
    if col != -1:
      raise newException(Exception, "Invalid UTF-8 data in line $1, byte $2".format(row+1, col+1))
    row.inc

proc joinLines*(lines: RefStrings): string =
  let lineCount = lines[].len
  var i = 0
  for line in lines[]:
    result &= line[]
    if i != lineCount - 1:
      result &= "\n"
    i.inc

proc add*(lines: var RefStrings, line: string) =
  var s: ref string
  new s
  s[] = line
  lines[].add(s)

proc set*(lines: var RefStrings, i: int, line: string) =
  var s: ref string
  new s
  s[] = line
  lines[i] = s

proc linesToTrees*(lines: RefStrings): seq[wavescript.CommandTree] =
  var scriptContext = waveScript.initContext()
  let
    cmds = wavescript.extract(sequtils.map(lines[], codes.stripCodesIfCommand))
    treesTemp = sequtils.map(cmds, proc (text: auto): wavescript.CommandTree = wavescript.parse(scriptContext, text))
  wavescript.parseOperatorCommands(treesTemp)

proc play*(events: seq[paramidi.Event]) =
  if iw.gIllwillInitialised:
    let
      (secs, playResult) = midi.play(events)
      startTime = times.epochTime()
    if playResult.kind == sound.Error:
      raise newException(Exception, playResult.message)
    while true:
      let currTime = times.epochTime() - startTime
      if currTime > secs:
        break
      let key = iw.getKey()
      if key == iw.Key.Tab:
        break
      os.sleep(constants.sleepMsecs)
    midi.stop(playResult.addrs)
  else:
    let currentTime = times.epochTime()
    let (secs, playResult) = midi.play(events)

proc compileAndPlayAll*(trees: seq[wavescript.CommandTree]) =
  var
    noErrors = true
    nodes = json.JsonNode(kind: json.JArray)
    midiContext = paramidi.initContext()
  for cmd in trees:
    if cmd.skip:
      continue
    let
      res =
        try:
          let node = wavescript.toJson(cmd)
          nodes.elems.add(node)
          midi.compileScore(midiContext, node, false)
        except Exception as e:
          midi.CompileResult(kind: midi.Error, message: e.msg)
    case res.kind:
    of midi.Valid:
      discard
    of midi.Error:
      noErrors = false
      break
  if noErrors:
    midiContext = paramidi.initContext()
    let res =
      try:
        midi.compileScore(midiContext, nodes, true)
      except Exception as e:
        midi.CompileResult(kind: midi.Error, message: e.msg)
    case res.kind:
    of midi.Valid:
      play(res.events)
    of midi.Error:
      discard

