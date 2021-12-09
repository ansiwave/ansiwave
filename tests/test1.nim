import unittest
from ./ansiwave import nil
from ./ansiwavepkg/codes import nil
import strutils

import ./ansiwavepkg/ansi
const content = staticRead("luke-and-yoda.ans")
stdout.write(ansiToUtf8(content))

test "Dedupe codes":
  const text = "\e[31m\e[32m\e[41;42;43mHello, world!\e[31m"
  let newText = codes.dedupeCodes(text)
  check newText.escape == "\e[32;43mHello, world!\e[31m".escape

  const text2 = "\e[0;1;22;36;1;22;1;22;1;22;1;46m"
  let newText2 = codes.dedupeCodes(text2)
  check newText2.escape == "\e[0;36;22;1;46m".escape

test "Dedupe RGB codes correctly":
  const text = "\e[38;2;255;255;255m"
  let newText = codes.dedupeCodes(text)
  check newText.escape == text.escape

  const text2 = "\e[0;38;2;4;6;8;48;2;114;129;163;38;2;114;129;163m"
  let newText2 = codes.dedupeCodes(text2)
  check newText2.escape == "\e[0;48;2;114;129;163;38;2;114;129;163m".escape

from zippy import nil
from base64 import nil

test "zlib compression":
  const text = staticRead("luke-and-yoda.ansiwave")
  const output = zippy.compress(text, dataFormat = zippy.dfZlib)
  let b64 = base64.encode(output, safe = true)
  check text == zippy.uncompress(base64.decode(b64), dataFormat = zippy.dfZlib)

from ./ansiwavepkg/codes import nil
import unicode

test "remove pointless clears":
  const
    before = "\e[0mH\e[0me\e[0ml\e[0ml\e[0mo!\e[30mWassup\e[0mG\e[0mr\e[0me\e[0metings"
    after = "\e[0mHello!\e[30mWassup\e[0mGreetings"
  check codes.dedupeCodes(before).escape == after.escape

from ./ansiwavepkg/chafa import nil

const img = staticRead("aintgottaexplainshit.jpg")

test "convert image to ansi art":
  try:
    echo chafa.imageToAnsi(img, 80)
  except:
    discard

import ./ansiwavepkg/qrcodegen

test "qrcode":
  const text = "Hello, world!"
  var qrcode: array[qrcodegen_BUFFER_LEN_MAX, uint8]
  var tempBuffer: array[qrcodegen_BUFFER_LEN_MAX, uint8]
  check qrcodegen_encodeText(text, tempBuffer.addr, qrcode.addr, qrcodegen_Ecc_LOW,
                             qrcodegen_VERSION_MIN, qrcodegen_VERSION_MAX, qrcodegen_Mask_AUTO, true);
  printQr(qrcode.addr)

from ./ansiwavepkg/user import nil
import stb_image/read as stbi

test "stego":
  var width, height, channels: int
  var data = stbi.loadFromMemory(cast[seq[uint8]](img), width, height, channels, stbi.RGBA)
  const message = "Hello, world!"
  user.stego(data, message)
  check message == user.destego(data)

