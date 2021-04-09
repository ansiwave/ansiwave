import parasound/dr_wav
import parasound/miniaudio

type
  Addrs* = (ptr ma_decoder, ptr ma_device)
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
  var
    decoder = newSeq[uint8](ma_decoder_size())
    decoderAddr = cast[ptr ma_decoder](decoder[0].addr)
    deviceConfig = newSeq[uint8](ma_device_config_size())
    deviceConfigAddr = cast[ptr ma_device_config](deviceConfig[0].addr)
    device = newSeq[uint8](ma_device_size())
    deviceAddr = cast[ptr ma_device](device[0].addr)
  when data is string:
    doAssert MA_SUCCESS == ma_decoder_init_file(data, nil, decoderAddr)
  elif data is seq[uint8]:
    doAssert MA_SUCCESS == ma_decoder_init_memory(data[0].unsafeAddr, data.len, nil, decoderAddr)

  proc data_callback(pDevice: ptr ma_device; pOutput: pointer; pInput: pointer; frameCount: ma_uint32) {.cdecl.} =
    let decoderAddr = ma_device_get_decoder(pDevice)
    discard ma_decoder_read_pcm_frames(decoderAddr, pOutput, frameCount)

  ma_device_config_init_with_decoder(deviceConfigAddr, ma_device_type_playback, decoderAddr, data_callback)
  if ma_device_init(nil, deviceConfigAddr, deviceAddr) != MA_SUCCESS:
    discard ma_decoder_uninit(decoderAddr)
    return PlayResult(kind: Error, message: "Failed to open playback device.")

  if ma_device_start(deviceAddr) != MA_SUCCESS:
    ma_device_uninit(deviceAddr)
    discard ma_decoder_uninit(decoderAddr)
    return PlayResult(kind: Error, message: "Failed to start playback device.")

  PlayResult(kind: Valid, addrs: (decoderAddr, deviceAddr))

proc stop*(decoderAddr: ptr ma_decoder, deviceAddr: ptr ma_device) =
  discard ma_device_stop(deviceAddr)
  ma_device_uninit(deviceAddr)
  discard ma_decoder_uninit(decoderAddr)

proc writeFile*(filename: string, data: var openArray[cshort], numSamples: uint32, sampleRate: uint32) =
  var
    wav: drwav
    format: drwav_data_format
  format.container = drwav_container_riff
  format.format = DR_WAVE_FORMAT_PCM
  format.channels = 1
  format.sampleRate = sampleRate
  format.bitsPerSample = 16
  doAssert drwav_init_file_write(wav.addr, filename, addr(format), nil)
  doAssert numSamples == drwav_write_pcm_frames(wav.addr, numSamples, data.addr)
  discard drwav_uninit(wav.addr)

proc writeMemory*(data: var openArray[cshort], numSamples: uint32, sampleRate: uint32): seq[uint8] =
  var
    wav: drwav
    format: drwav_data_format
  format.container = drwav_container_riff
  format.format = DR_WAVE_FORMAT_PCM
  format.channels = 1
  format.sampleRate = sampleRate
  format.bitsPerSample = 16
  var
    outputRaw: pointer
    outputSize: csize
  doAssert drwav_init_memory_write_sequential(wav.addr, outputRaw.addr, outputSize.addr, format.addr, numSamples, nil)
  doAssert numSamples == drwav_write_pcm_frames(wav.addr, numSamples, data[0].addr)
  doAssert outputSize > 0
  result = newSeq[uint8](outputSize)
  copyMem(result[0].addr, outputRaw, outputSize)
  drwav_free(outputRaw, nil)
  discard drwav_uninit(wav.addr)
