import unittest
from ./ansiwave import nil
from ./ansiwavepkg/codes import nil
from ./ansiwavepkg/ui/editor import nil
import strutils, sequtils

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

from ./ansiwavepkg/wavescript import nil

proc parseAnsiwave(lines: ref seq[ref string]): seq[wavescript.CommandTree] =
  var scriptContext = waveScript.initContext()
  let
    cmds = wavescript.parse(sequtils.map(lines[], codes.stripCodesIfCommand))
    treesTemp = sequtils.map(cmds, proc (text: auto): wavescript.CommandTree = wavescript.parse(scriptContext, text))
  wavescript.parseOperatorCommands(treesTemp)

test "Parse commands":
  const hello = staticRead("hello.ansiwave")
  let lines = editor.splitLines(hello)
  let trees = parseAnsiwave(lines)
  check trees.len == 2

test "Parse operators":
  let lines = editor.splitLines("/rock-organ c#+3 /octave 3 d-,c /2 1/2 c,d c+")
  let trees = parseAnsiwave(lines)
  check trees.len == 1

test "Parse broken symbol":
  let lines = editor.splitLines("/instrument -hello-world")
  let trees = parseAnsiwave(lines)
  check trees.len == 1

test "/,":
  let text = editor.splitLines("""
/banjo /octave 3 /16 b c+ /8 d+ b c+ a b g a
/,
/guitar /octave 3 /16 r r /8 g r d r g g d
""")
  let trees = parseAnsiwave(text)
  check trees.len == 3

test "variables":
  const text = staticRead("variables.ansiwave")
  let lines = editor.splitLines(text)
  let trees = parseAnsiwave(lines)
  check trees.len == 4

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

test "convert image to ansi art":
  const img = staticRead("aintgottaexplainshit.jpg")
  try:
    echo chafa.imageToAnsi(img, 80)
  except:
    discard

import ./ansiwavepkg/qrcodegen

test "qrcode":
  const text = "Hello, world!"
  var qrcode: array[qrcodegen_BUFFER_LEN_MAX, uint8]
  var tempBuffer: array[qrcodegen_BUFFER_LEN_MAX, uint8]
  check 1 == qrcodegen_encodeText(text, tempBuffer.addr, qrcode.addr, qrcodegen_Ecc_LOW,
    qrcodegen_VERSION_MIN, qrcodegen_VERSION_MAX, qrcodegen_Mask_AUTO, 1);
  printQr(qrcode.addr)

