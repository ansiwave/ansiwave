# Package

version       = "0.1.0"
author        = "oakes"
description   = "FIXME"
license       = "Public Domain"
srcDir        = "src"
bin           = @["ansigui"]

task dev, "Run dev version":
  exec "nimble run ansigui"

# Dependencies

requires "nim >= 1.6.4"
requires "paranim >= 0.12.0"
requires "paratext >= 0.13.0"
requires "https://github.com/ansiwave/ansiwave_bbs#d78b128"
