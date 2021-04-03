from sound import nil
import paramidi
import paramidi/tsf
import paramidi_soundfonts

const
  score =
    (piano,
      (tempo: 74),
      (1/8, {-d, -a, e, fx}, a,
       1/2, {fx, +d},
       1/8, {-e, e, +c}, a,
       1/2, {c, e},
       1/8, {-d, -a, e, fx}, a, +d, +cx, +e, +d, b, +cx,
       1/2, {-e, c, a}, 1/2, {c, e}))

proc play*(): (int, sound.Addrs) =
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
  var res = render[cshort](compile(score), sf, sampleRate)
  # create the wav file and play it
  const padding = 500f # add a half second so it doesn't cut off abruptly
  let wav = sound.writeMemory(res.data, res.data.len.uint32, sampleRate)
  let addrs = sound.play(wav)
  (int(res.seconds * 1000f + padding), addrs)

proc stop*(addrs: sound.Addrs) =
  sound.stop(addrs[0], addrs[1])
