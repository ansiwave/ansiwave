import parasound/dr_wav
import parasound/miniaudio

type
  AddrsKind = enum
    FromWeb, FromFile, FromMemory,
  Addrs* = object
    engine*: ref seq[uint8]
    case kind*: AddrsKind
    of FromWeb, FromFile:
      discard
    of FromMemory:
      decoder*: ref seq[uint8]
      sound*: ref seq[uint8]
  ResultKind* = enum
    Valid, Error,
  PlayResult* = object
    case kind*: ResultKind
    of Valid:
      addrs*: Addrs
    of Error:
      message*: string

proc play*(data: string | seq[uint8]): PlayResult =
  ## if `data` is a string, it is interpreted as a filename.
  ## if `data` is a byte sequence, it is interpreted as an in-memory buffer.
  var engine: ref seq[uint8]
  new engine
  engine[] = newSeq[uint8](ma_engine_size())
  if MA_SUCCESS != ma_engine_init(nil, engine[0].addr):
    return PlayResult(kind: Error, message: "Failed to init engine.")
  when data is string:
    if MA_SUCCESS != ma_engine_play_sound(engine[0].addr, data, nil):
      ma_engine_uninit(engine[0].addr)
      return PlayResult(kind: Error, message: "Failed to play sound.")
    PlayResult(kind: Valid, addrs: Addrs(kind: FromFile, engine: engine))
  elif data is seq[uint8]:
    var decoder: ref seq[uint8]
    new decoder
    decoder[] = newSeq[uint8](ma_decoder_size())
    if MA_SUCCESS != ma_decoder_init_memory(data[0].unsafeAddr, data.len.csize_t, nil, decoder[0].addr):
      ma_engine_uninit(engine[0].addr)
      return PlayResult(kind: Error, message: "Failed to init decoder.")
    var sound: ref seq[uint8]
    new sound
    sound[] = newSeq[uint8](ma_sound_size())
    if MA_SUCCESS != ma_sound_init_from_data_source(engine[0].addr, decoder[0].addr, 0, nil, sound[0].addr):
      discard ma_decoder_uninit(decoder[0].addr)
      ma_engine_uninit(engine[0].addr)
      return PlayResult(kind: Error, message: "Failed to init sound.")
    if MA_SUCCESS != ma_sound_start(sound[0].addr):
      ma_sound_uninit(sound[0].addr)
      discard ma_decoder_uninit(decoder[0].addr)
      ma_engine_uninit(engine[0].addr)
      return PlayResult(kind: Error, message: "Failed to start sound.")
    PlayResult(kind: Valid, addrs: Addrs(kind: FromMemory, engine: engine, decoder: decoder, sound: sound))

proc stop*(addrs: Addrs) =
  case addrs.kind:
  of FromWeb:
    discard
  of FromFile:
    ma_engine_uninit(addrs.engine[0].unsafeAddr)
  of FromMemory:
    ma_sound_uninit(addrs.sound[0].unsafeAddr)
    discard ma_decoder_uninit(addrs.decoder[0].unsafeAddr)
    ma_engine_uninit(addrs.engine[0].unsafeAddr)

proc writeFile*(filename: string, data: var openArray[cshort], numSamples: uint32, sampleRate: uint32) =
  var
    wav = newSeq[uint8](drwav_size())
    format: drwav_data_format
  format.container = drwav_container_riff
  format.format = DR_WAVE_FORMAT_PCM
  format.channels = 1
  format.sampleRate = sampleRate
  format.bitsPerSample = 16
  doAssert drwav_init_file_write(wav[0].addr, filename, addr(format), nil)
  doAssert numSamples == drwav_write_pcm_frames(wav[0].addr, numSamples, data.addr)
  discard drwav_uninit(wav[0].addr)

proc writeMemory*(data: var openArray[cshort], numSamples: uint32, sampleRate: uint32): seq[uint8] =
  var
    wav = newSeq[uint8](drwav_size())
    format: drwav_data_format
  format.container = drwav_container_riff
  format.format = DR_WAVE_FORMAT_PCM
  format.channels = 1
  format.sampleRate = sampleRate
  format.bitsPerSample = 16
  var
    outputRaw: pointer
    outputSize: csize_t
  doAssert drwav_init_memory_write_sequential(wav[0].addr, outputRaw.addr, outputSize.addr, format.addr, numSamples, nil)
  doAssert numSamples == drwav_write_pcm_frames(wav[0].addr, numSamples, data[0].addr)
  doAssert outputSize > 0
  result = newSeq[uint8](outputSize)
  copyMem(result[0].addr, outputRaw, outputSize)
  drwav_free(outputRaw, nil)
  discard drwav_uninit(wav[0].addr)

