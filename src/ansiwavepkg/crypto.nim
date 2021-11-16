from stb_image/write as stbiw import nil
from ./qrcodegen import nil
from wavecorepkg/ed25519 import nil
from wavecorepkg/paths import nil
from ./storage import nil
import json
import stb_image/read as stbi
import bitops

proc stego*(image: var seq[uint8], message: string) =
  var bits: seq[bool]

  # for now, we only store in the least significant bit
  # but maybe later it would be nice to use more
  const sigbits = 0'u8
  for i in 0 ..< 3:
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
  for i in 0 ..< 3:
    if image[pos + i].bitand(1) == 1:
      sigbits.setBit(i)
    else:
      sigbits.clearBit(i)
  pos += 3

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

const
  algorithm* = "ed25519"
  loginKeyName = "login-key.png"

var
  keyPair: ed25519.KeyPair
  pubKey*: string
  image: seq[uint8]

proc loadKey*(privateKey: seq[uint8]) =
  try:
    var width, height, channels: int
    let
      data = stbi.loadFromMemory(privateKey, width, height, channels, stbi.RGBA)
      json = destego(data)
    if json != "":
      let
        obj = parseJson(json)
        privKey = paths.decode(obj["private-key"].str)
      doAssert privKey.len == keyPair.private.len
      keyPair = ed25519.initKeyPair(cast[ed25519.PrivateKey](privKey[0]))
      pubKey = paths.encode(keyPair.public)
      image = privateKey
  except Exception as ex:
    discard

proc loadKey*() =
  let privateKey = cast[seq[uint8]](storage.get(loginKeyName, isBinary = true))
  if privateKey.len > 0:
    loadKey(privateKey)

proc removeKey*() =
  storage.remove(loginKeyName)
  keyPair = ed25519.KeyPair()
  pubKey = ""
  image = @[]

when defined(emscripten):
  from wavecorepkg/client/emscripten import nil
  from base64 import nil

  var callback: proc () = nil

  proc browsePrivateKey*(cb: proc ()) =
    callback = cb
    emscripten.browseFile("insertPrivateKey")

  proc free(p: pointer) {.importc.}

  proc insertPrivateKey(name: cstring, image: pointer, length: cint) {.exportc.} =
    let
      img = block:
        var s = newSeq[uint8](length)
        copyMem(s[0].addr, image, length)
        free(image)
        s
    loadKey(img)
    discard storage.set(loginKeyName, img, isBinary = true)
    if callback != nil:
      callback()
      callback = nil

when defined(emscripten):
  proc downloadKey*() =
    if image.len > 0:
      let b64 = base64.encode(image)
      emscripten.startDownload("data:image/png;base64," & b64, "login-key.png")

proc createUser*() =
  keyPair = ed25519.initKeyPair()
  pubKey = paths.encode(keyPair.public)

  let privateKey = paths.encode(keyPair.private)

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

  image = stbiw.writePNG(width, height, 4, data)
  discard storage.set(loginKeyName, image, isBinary = true)

  when defined(emscripten):
    downloadKey()
