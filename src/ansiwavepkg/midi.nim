from sound import nil
import paramidi
import paramidi/tsf
import paramidi_soundfonts
import json

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

proc play*(events: seq[Event]): tuple[secs: float, addrs: sound.Addrs] =
  # get the sound font
  # in a release build, embed it in the binary.
  when defined(release):
    const soundfont = staticRead("paramidi_soundfonts/generaluser.sf2")
    var sf = tsf_load_memory(soundfont.cstring, soundfont.len.cint)
  # during dev, read it from the disk
  else:
    var sf = tsf_load_filename(paramidi_soundfonts.getSoundFontPath("generaluser.sf2"))
  # render the score
  const sampleRate = 44100
  tsf_set_output(sf, TSF_MONO, sampleRate, 0)
  var res = render[cshort](events, sf, sampleRate)
  # create the wav file and play it
  let wav = sound.writeMemory(res.data, res.data.len.uint32, sampleRate)
  let addrs = sound.play(wav)
  (secs: res.seconds, addrs: addrs)

proc stop*(addrs: sound.Addrs) =
  sound.stop(addrs[0], addrs[1])
