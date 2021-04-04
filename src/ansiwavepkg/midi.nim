from sound import nil
import paramidi
import paramidi/tsf
import paramidi_soundfonts
import json

type
  ResultKind* = enum
    Valid, Error,
  Result* = object
    case kind*: ResultKind
    of Valid:
      msecs*: int
      addrs*: sound.Addrs
    of Error:
      message*: string

proc play*(score: JsonNode): Result =
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
  let compiledScore =
    try:
      compile(score)
    except Exception as e:
      return Result(kind: Error, message: e.msg)
  var res = render[cshort](compiledScore, sf, sampleRate)
  # create the wav file and play it
  const padding = 500f # add a half second so it doesn't cut off abruptly
  let wav = sound.writeMemory(res.data, res.data.len.uint32, sampleRate)
  let addrs = sound.play(wav)
  Result(kind: Valid, msecs: int(res.seconds * 1000f + padding), addrs: addrs)

proc stop*(addrs: sound.Addrs) =
  sound.stop(addrs[0], addrs[1])
