import unittest
from zippy import nil
from base64 import nil

test "zlib compression":
  const text = staticRead("luke-and-yoda.ansiwave")
  let output = zippy.compress(text, dataFormat = zippy.dfZlib)
  let b64 = base64.encode(output, safe = true)
  check text == zippy.uncompress(base64.decode(b64), dataFormat = zippy.dfZlib)

from ansiwavepkg/chafa import nil

const img = staticRead("aintgottaexplainshit.jpg")

test "convert image to ansi art":
  echo chafa.imageToAnsi(img, 80)

import ansiwavepkg/qrcodegen

test "qrcode":
  const text = "Hello, world!"
  var qrcode: array[qrcodegen_BUFFER_LEN_MAX, uint8]
  var tempBuffer: array[qrcodegen_BUFFER_LEN_MAX, uint8]
  check qrcodegen_encodeText(text, tempBuffer.addr, qrcode.addr, qrcodegen_Ecc_LOW,
                             qrcodegen_VERSION_MIN, qrcodegen_VERSION_MAX, qrcodegen_Mask_AUTO, true);
  printQr(qrcode.addr)

from ansiwavepkg/user import nil
import stb_image/read as stbi

test "stego":
  var width, height, channels: int
  var data = stbi.loadFromMemory(cast[seq[uint8]](img), width, height, channels, stbi.RGBA)
  const message = "Hello, world!"
  user.stego(data, message)
  check message == user.destego(data)

from ansiwavepkg/ui/editor import nil
from illwave as iw import `[]`, `[]=`, `==`
from times import nil
import pararules
from ansiwavepkg/ui/context import nil

test "editor perf":
  let t1 = times.cpuTime()
  var
    session = editor.init(editor.Options(), 80, 40)
    ctx = context.initContext()
    focused = false
  ctx.tb = iw.initTerminalBuffer(80, 40)
  for _ in 0 ..< 10:
    for _ in 0 ..< 10:
      editor.tick(session, ctx, (iw.Key.A, 0'u32), focused)
      session.fireRules
    editor.tick(session, ctx, (iw.Key.Enter, 0'u32), focused)
    session.fireRules
  let t2 = times.cpuTime()
  echo t2 - t1, " seconds"
