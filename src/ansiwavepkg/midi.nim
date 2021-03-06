from ./sound import nil
import paramidi
import paramidi/tsf
import paramidi_soundfonts
import json

when defined(emscripten):
  from wavecorepkg/client import nil
  from ./emscripten import nil
  from base64 import nil

  var response: client.ChannelValue[client.Response]

  proc fetchSoundfont() =
    var clnt = client.initClient("")
    response = client.query(clnt, "soundfont.sf2")

  proc soundfontReady*(): bool =
    if not response.started:
      fetchSoundfont()
    client.get(response)
    response.ready
else:
  proc soundfontReady*(): bool =
    true

type
  ResultKind* = enum
    Valid, Error,
  CompileResult* = object
    case kind*: ResultKind
    of Valid:
      events*: seq[Event]
    of Error:
      message*: string
  PlayResult* = tuple[secs: float, playResult: sound.PlayResult]

const endRestSeconds = 10.0

proc compileScore*(ctx: var Context, score: JsonNode, padding: bool): CompileResult =
  # add a quarter note rest to prevent it from ending abruptly
  var s = score
  if padding and s.kind == JArray:
    s = JsonNode(kind: JArray, elems: @[s])
    s.elems.add(JsonNode(kind: JFloat, fnum: 1/4))
    s.elems.add(JsonNode(kind: JString, str: "r"))
    # on native, add 10 seconds to lengthen the clip,
    # because very short audio data doesn't play correctly for some reason
    when not defined(emscripten):
      s.elems.add(JsonNode(kind: JFloat, fnum: endRestSeconds / 2))
      s.elems.add(JsonNode(kind: JString, str: "r"))
  let compiledScore =
    try:
      paramidi.compile(ctx, s)
    except Exception as e:
      return CompileResult(kind: Error, message: e.msg)
  CompileResult(kind: Valid, events: compiledScore)

proc play*(events: seq[Event], outputFile: string = ""): PlayResult =
  if events.len == 0:
    return
  # get the sound font
  # in a release build, embed it in the binary.
  when defined(emscripten):
    if not soundfontReady():
      return (0.0, sound.PlayResult(kind: sound.Error, message: "Still fetching soundfont, try again soon."))
    elif response.value.kind == client.Error:
      return (0.0, sound.PlayResult(kind: sound.Error, message: response.value.error))
    elif response.value.valid.code != 200:
      return (0.0, sound.PlayResult(kind: sound.Error, message: "Failed to fetch soundfont"))
    let soundfont = response.value.valid.body
    var sf = tsf_load_memory(soundfont.cstring, soundfont.len.cint)
  elif defined(release):
    const soundfont = staticRead("paramidi_soundfonts/aspirin.sf2")
    var sf = tsf_load_memory(soundfont.cstring, soundfont.len.cint)
  # during dev, read it from the disk
  else:
    let path = paramidi_soundfonts.getSoundFontPath("aspirin.sf2")
    var sf = tsf_load_filename(path.cstring)
  # render the score
  const sampleRate = 44100
  tsf_set_output(sf, TSF_MONO, sampleRate, 0)
  var res = render[cshort](events, sf, sampleRate)
  tsf_close(sf)
  const maxSeconds = 60 * 60 * 1 # 1 hour
  if res.seconds > maxSeconds:
    return (secs: res.seconds, playResult: sound.PlayResult(kind: sound.Error, message: "Audio exceeds max length"))
  # create the wav file and play it
  if outputFile != "":
    sound.writeFile(outputFile, res.data, res.data.len.uint32, sampleRate)
    (secs: res.seconds, playResult: sound.PlayResult(kind: sound.Error, message: "Only writing to disk"))
  else:
    let wav = sound.writeMemory(res.data, res.data.len.uint32, sampleRate)
    when defined(emscripten):
      emscripten.playAudio("data:audio/wav;base64," & base64.encode(wav))
      (secs: res.seconds, playResult: sound.PlayResult(kind: sound.Valid, addrs: sound.Addrs(kind: sound.FromWeb)))
    else:
      (secs: res.seconds - endRestSeconds, playResult: sound.play(wav))

proc stop*(addrs: sound.Addrs) =
  when defined(emscripten):
    emscripten.stopAudio()
  else:
    sound.stop(addrs)
