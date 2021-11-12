from stb_image/write as stbiw import nil
from ./qrcodegen import nil
from wavecorepkg/ed25519 import nil
from wavecorepkg/base58 import nil
from os import `/`

when defined(emscripten):
  from wavecorepkg/client/emscripten import nil
  from base64 import nil

const
  loginKeyDir = "~" / ".cache" / "ansiwave"
  loginKeyName = "login-key.png"
  loginKeyPath = loginKeyDir / loginKeyName

proc createUser*() =
  let
    pair = ed25519.initKeyPair()
    text = base58.encode(pair.private)

  var qrcode: array[qrcodegen.qrcodegen_BUFFER_LEN_MAX, uint8]
  var tempBuffer: array[qrcodegen.qrcodegen_BUFFER_LEN_MAX, uint8]
  if not qrcodegen.qrcodegen_encodeText(text, tempBuffer.addr, qrcode.addr, qrcodegen.qrcodegen_Ecc_LOW,
                                        qrcodegen.qrcodegen_VERSION_MIN, qrcodegen.qrcodegen_VERSION_MAX,
                                        qrcodegen.qrcodegen_Mask_AUTO, true):
    return

  let
    size = qrcodegen.qrcodegen_getSize(qrcode.addr)
    blockSize = 10'i32
    width = blockSize * size
    height = blockSize * size

  var data: seq[uint8] = @[]

  for y in 0 ..< width:
    for x in 0 ..< height:
      let
        blockY = cint(y / blockSize)
        blockX = cint(x / blockSize)
        fill = qrcodegen.qrcodegen_getModule(qrcode.addr, blockX, blockY)
      data.add(if fill: 0 else: 255)
      data.add(if fill: 0 else: 255)
      data.add(if fill: 0 else: 255)
      data.add(255)

  when defined(emscripten):
    let
      png = stbiw.writePNG(width, height, 4, data)
      b64 = base64.encode(png)
    emscripten.startDownload("data:image/png;base64," & b64, "login-key.png")
  else:
    os.createDir(os.expandTilde(loginKeyDir))
    stbiw.writePNG(os.expandTilde(loginKeyPath), width, height, 4, data)

proc keyExists*(): bool =
  when defined(emscripten):
    false
  else:
    os.fileExists(os.expandTilde(loginKeyPath))

