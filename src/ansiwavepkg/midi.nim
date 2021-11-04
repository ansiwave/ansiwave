from ./sound import nil
import paramidi
import paramidi/tsf
import paramidi_soundfonts
import json
from os import nil

type
  ResultKind* = enum
    Valid, Error,
  CompileResult* = object
    case kind*: ResultKind
    of Valid:
      events*: seq[Event]
    of Error:
      message*: string

proc compileScore*(ctx: var Context, score: JsonNode, padding: bool): CompileResult =
  # add a quarter note rest to prevent it from ending abruptly
  var s = score
  if padding and s.kind == JArray:
    s = JsonNode(kind: JArray, elems: @[s])
    s.elems.add(JsonNode(kind: JFloat, fnum: 1/4))
    s.elems.add(JsonNode(kind: JString, str: "r"))
  let compiledScore =
    try:
      paramidi.compile(ctx, s)
    except Exception as e:
      return CompileResult(kind: Error, message: e.msg)
  CompileResult(kind: Valid, events: compiledScore)

proc play*(events: seq[Event], outputFile: string = ""): tuple[secs: float, playResult: sound.PlayResult] =
  # get the sound font
  # in a release build, embed it in the binary.
  when defined(emscripten):
    var sf = cast[ptr tsf](nil)
    raise newException(Exception, "Not supported for now")
  elif defined(release):
    # if there is a soundfont in the root of this repo, use it.
    # otherwise, use a soundfont from paramidi_soundfonts
    const soundfont =
      when os.fileExists("soundfont.sf2"):
        staticRead("../../soundfont.sf2")
      else:
        staticRead("paramidi_soundfonts/generaluser.sf2")
    var sf = tsf_load_memory(soundfont.cstring, soundfont.len.cint)
  # during dev, read it from the disk
  else:
    var sf = tsf_load_filename(paramidi_soundfonts.getSoundFontPath("generaluser.sf2"))
  # render the score
  const sampleRate = 44100
  tsf_set_output(sf, TSF_MONO, sampleRate, 0)
  var res = render[cshort](events, sf, sampleRate)
  # create the wav file and play it
  if outputFile != "":
    sound.writeFile(outputFile, res.data, res.data.len.uint32, sampleRate)
    (secs: res.seconds, playResult: sound.PlayResult(kind: sound.Error, message: "Only writing to disk"))
  else:
    let wav = sound.writeMemory(res.data, res.data.len.uint32, sampleRate)
    (secs: res.seconds, playResult: sound.play(wav))

proc stop*(addrs: sound.Addrs) =
  sound.stop(addrs[0], addrs[1])
