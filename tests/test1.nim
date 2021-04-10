import unittest
from ansiwavepkg/codes import nil
import strutils, sequtils

import ansiwavepkg/ansi
const content = staticRead("luke_and_yoda.ans")
print(ansiToUtf8(content))

test "Dedupe codes":
  const text = "\e[31m\e[32m\e[41;42;43mHello, world!\e[31m"
  let newText = codes.dedupeCodes(text)
  check newText.escape == "\e[32;43mHello, world!\e[31m".escape

from ansiwavepkg/wavescript import nil

const hello = staticRead("hello.ansiwave")

test "Parse commands":
  const text = strutils.splitLines(hello)
  var scriptContext = waveScript.initContext()
  let
    cmds = wavescript.parse(text)
    treesTemp = sequtils.map(cmds, proc (text: auto): wavescript.CommandTree = wavescript.parse(scriptContext, text))
    trees = wavescript.parseOperatorCommands(treesTemp)
  check trees.len == 2

test "Parse operators":
  const text = @["/rock-organ c#+3 /octave 3 d-,c /2 1/2 c,d c+"]
  var scriptContext = waveScript.initContext()
  let
    cmds = wavescript.parse(text)
    treesTemp = sequtils.map(cmds, proc (text: auto): wavescript.CommandTree = wavescript.parse(scriptContext, text))
    trees = wavescript.parseOperatorCommands(treesTemp)
  check trees.len == 1

test "/,":
  const text = @[
    "/banjo /octave 3 /16 b c+ /8 d+ b c+ a b g a",
    "/,",
    "/guitar /octave 3 /16 r r /8 g r d r g g d",
  ]
  var scriptContext = waveScript.initContext()
  let
    cmds = wavescript.parse(text)
    treesTemp = sequtils.map(cmds, proc (text: auto): wavescript.CommandTree = wavescript.parse(scriptContext, text))
    trees = wavescript.parseOperatorCommands(treesTemp)
  check trees.len == 3

test "variables":
  const text = strutils.splitLines(staticRead("variables.ansiwave"))
  var scriptContext = waveScript.initContext()
  let
    cmds = wavescript.parse(text)
    treesTemp = sequtils.map(cmds, proc (text: auto): wavescript.CommandTree = wavescript.parse(scriptContext, text))
    trees = wavescript.parseOperatorCommands(treesTemp)
  check trees.len == 4

#[
from zippy import nil
from base64 import nil

test "zlib compression":
  const output = zippy.compress(hello, dataFormat = zippy.dfZlib)
  echo base64.encode(output, safe = true)
]#
