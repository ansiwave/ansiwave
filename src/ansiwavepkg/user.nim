from stb_image/write as stbiw import nil
from ./qrcodegen import nil
from wavecorepkg/ed25519 import nil
from wavecorepkg/paths import nil
from ./storage import nil
import json
import stb_image/read as stbi
import bitops
from strutils import nil

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

const loginKeyName = "login-key.png"

var
  keyPair*: ed25519.KeyPair
  pubKey*: string

proc loadKey*(privateKeyStr: string) =
  let privKeyStr = paths.decode(privateKeyStr)
  doAssert privKeyStr.len == keyPair.private.len
  var privKey: ed25519.PrivateKey
  copyMem(privKey.addr, privKeyStr[0].unsafeAddr, privKeyStr.len)
  keyPair = ed25519.initKeyPair(privKey)
  pubKey = paths.encode(keyPair.public)

proc loadImage*(privateKeyImage: seq[uint8]) =
  try:
    var width, height, channels: int
    let
      data = stbi.loadFromMemory(privateKeyImage, width, height, channels, stbi.RGBA)
      json = destego(data)
    if json != "":
      let obj = parseJson(json)
      loadKey(obj["private-key"].str)
  except Exception as ex:
    discard

proc loadKey*() =
  let privateKey = cast[seq[uint8]](storage.get(loginKeyName, isBinary = true))
  if privateKey.len > 0:
    loadImage(privateKey)

proc removeKey*() =
  storage.remove(loginKeyName)
  keyPair = ed25519.KeyPair()
  pubKey = ""

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
    loadImage(img)
    discard storage.set(loginKeyName, img, isBinary = true)
    if callback != nil:
      callback()
      callback = nil

  proc downloadImage*(image: seq[uint8]) =
    if image.len > 0:
      let b64 = base64.encode(image)
      emscripten.startDownload("data:image/png;base64," & b64, "login-key.png")

  proc downloadImage*() =
    downloadImage(cast[seq[uint8]](storage.get(loginKeyName, isBinary = true)))

proc createImage*(privateKey: ed25519.PrivateKey): seq[uint8] =
  let privateKey = paths.encode(privateKey)

  var fragments: seq[string]
  let pairs = {
    "key": privateKey,
    "algo": "ed25519",
  }
  for pair in pairs:
    if pair[1].len > 0:
      fragments.add(pair[0] & ":" & pair[1])
  let address = paths.address & "#" & strutils.join(fragments, ",")

  var qrcode: array[qrcodegen.qrcodegen_BUFFER_LEN_MAX, uint8]
  var tempBuffer: array[qrcodegen.qrcodegen_BUFFER_LEN_MAX, uint8]
  if not qrcodegen.qrcodegen_encodeText(address.cstring, tempBuffer.addr, qrcode.addr, qrcodegen.qrcodegen_Ecc_LOW,
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
  stbiw.writePNG(width, height, 4, data)

proc createUser*() =
  keyPair = ed25519.initKeyPair()
  pubKey = paths.encode(keyPair.public)
  let image = createImage(keyPair.private)
  discard storage.set(loginKeyName, image, isBinary = true)
  loadImage(image)
  when defined(emscripten):
    downloadImage(image)

proc createUser*(privateKeyStr: string, algo: string): bool =
  try:
    doAssert algo == "ed25519"
    loadKey(privateKeyStr)
    let image = createImage(keyPair.private)
    discard storage.set(loginKeyName, image, isBinary = true)
    true
  except Exception as ex:
    false

proc genLoginKey*(): seq[uint8] =
  let
    keyPair = ed25519.initKeyPair()
    pubKey = paths.encode(keyPair.public)
  echo pubKey
  createImage(keyPair.private)

