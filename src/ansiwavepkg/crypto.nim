from stb_image/write as stbiw import nil
from ./qrcodegen import nil
from wavecorepkg/ed25519 import nil
from base64 import nil
from ./storage import nil
import json
import stb_image/read as stbi

when defined(emscripten):
  from wavecorepkg/client/emscripten import nil
  from base64 import nil

import bitops

proc stego*(image: var seq[uint8], message: string) =
  var bits: seq[bool]

  # for now, we only store in the least significant bit
  # but maybe later it would be nice to use more
  const sigbits = 0'u8
  for i in 0 ..< 8:
    bits.add(sigbits.rotateRightBits(i).bitand(1) == 1)

  let length = message.len.uint32
  for i in 0 ..< 32:
    bits.add(length.rotateRightBits(i).bitand(1) == 1)

  for ch in message:
    for i in 0 ..< 8:
      bits.add(ch.uint8.rotateRightBits(i).bitand(1) == 1)

  for i in 0 ..< bits.len:
    if bits[i]:
      image[i].setBit(0)
    else:
      image[i].clearBit(0)

proc destego*(image: seq[uint8]): string =
  var pos = 0

  var sigbits: uint8
  for i in 0 ..< 8:
    if image[pos + i].bitand(1) == 1:
      sigbits.setBit(i)
    else:
      sigbits.clearBit(i)
  pos += 8

  if sigbits != 0:
    return ""

  var length: uint32
  for i in 0 ..< 32:
    if image[pos + i].bitand(1) == 1:
      length.setBit(i)
    else:
      length.clearBit(i)
  pos += 32

  for _ in 0 ..< length:
    var ch: uint8
    for i in 0 ..< 8:
      if image[pos + i].bitand(1) == 1:
        ch.setBit(i)
      else:
        ch.clearBit(i)
    result &= ch.char
    pos += 8

const loginKeyName = "login-key.png"

var
  keyPair: ed25519.KeyPair
  pubKey*: string

proc loadKey*() =
  let val = storage.get(loginKeyName, isBinary = true)
  if val != "":
    var width, height, channels: int
    let
      data = stbi.loadFromMemory(cast[seq[uint8]](val), width, height, channels, stbi.RGBA)
      json = destego(data)
    if json != "":
      try:
        let
          obj = parseJson(json)
          privKey = base64.decode(obj["private-key"].str)
        doAssert privKey.len == keyPair.private.len
        keyPair = ed25519.initKeyPair(cast[ed25519.PrivateKey](privKey[0]))
        pubKey = base64.encode(keyPair.public, safe = true)
      except Exception as ex:
        discard

proc removeKey*() =
  storage.remove(loginKeyName)
  keyPair = ed25519.KeyPair()
  pubKey = ""

proc createUser*() =
  keyPair = ed25519.initKeyPair()
  pubKey = base64.encode(keyPair.public, safe = true)

  let privateKey = base64.encode(keyPair.private, safe = true)

  var qrcode: array[qrcodegen.qrcodegen_BUFFER_LEN_MAX, uint8]
  var tempBuffer: array[qrcodegen.qrcodegen_BUFFER_LEN_MAX, uint8]
  if not qrcodegen.qrcodegen_encodeText(privateKey.cstring, tempBuffer.addr, qrcode.addr, qrcodegen.qrcodegen_Ecc_LOW,
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

  stego(data, $ %* {"private-key": privateKey, "algo": "ed25519"})

  let png = stbiw.writePNG(width, height, 4, data)
  discard storage.set(loginKeyName, png, isBinary = true)

  when defined(emscripten):
    let b64 = base64.encode(png)
    emscripten.startDownload("data:image/png;base64," & b64, "login-key.png")

