import unittest
from ansiwave import nil
from ansiwavepkg/codes import nil
import strutils, sequtils

import ansiwavepkg/ansi
const content = staticRead("luke-and-yoda.ans")
stdout.write(ansiToUtf8(content))

test "Dedupe codes":
  const text = "\e[31m\e[32m\e[41;42;43mHello, world!\e[31m"
  let newText = codes.dedupeCodes(text)
  check newText.escape == "\e[32;43mHello, world!\e[31m".escape

from ansiwavepkg/wavescript import nil

proc parseAnsiwave(lines: ref seq[ref string]): seq[wavescript.CommandTree] =
  var scriptContext = waveScript.initContext()
  let
    cmds = wavescript.parse(sequtils.map(lines[], codes.stripCodesIfCommand))
    treesTemp = sequtils.map(cmds, proc (text: auto): wavescript.CommandTree = wavescript.parse(scriptContext, text))
  wavescript.parseOperatorCommands(treesTemp)

test "Parse commands":
  const hello = staticRead("hello.ansiwave")
  let lines = ansiwave.splitLines(hello)
  let trees = parseAnsiwave(lines)
  check trees.len == 2

test "Parse operators":
  let lines = ansiwave.splitLines("/rock-organ c#+3 /octave 3 d-,c /2 1/2 c,d c+")
  let trees = parseAnsiwave(lines)
  check trees.len == 1

test "Parse broken symbol":
  let lines = ansiwave.splitLines("/instrument -hello-world")
  let trees = parseAnsiwave(lines)
  check trees.len == 1

test "/,":
  let text = ansiwave.splitLines("""
/banjo /octave 3 /16 b c+ /8 d+ b c+ a b g a
/,
/guitar /octave 3 /16 r r /8 g r d r g g d
""")
  let trees = parseAnsiwave(text)
  check trees.len == 3

test "variables":
  const text = staticRead("variables.ansiwave")
  let lines = ansiwave.splitLines(text)
  let trees = parseAnsiwave(lines)
  check trees.len == 4

from zippy import nil
from base64 import nil

test "zlib compression":
  const text = staticRead("luke-and-yoda.ansiwave")
  const output = zippy.compress(text, dataFormat = zippy.dfZlib)
  let b64 = base64.encode(output, safe = true)
  check text == zippy.uncompress(base64.decode(b64), dataFormat = zippy.dfZlib)

from ansiwavepkg/codes import nil
import unicode

test "remove pointless clears":
  const
    before = "\e[0mH\e[0me\e[0ml\e[0ml\e[0mo!\e[30mWassup\e[0mG\e[0mr\e[0me\e[0metings"
    after = "\e[0mHello!\e[30mWassup\e[0mGreetings"
  check codes.dedupeCodes(before).escape == after.escape
