# Package

version       = "0.1.0"
author        = "oakes"
description   = "A new awesome nimble package"
license       = "Public Domain"
srcDir        = "src"
installExt    = @["nim"]
bin           = @["ansiwave"]

task dev, "Run dev version":
  exec "nimble run ansiwave"

# Dependencies

requires "nim >= 1.4.4"
requires "pararules >= 0.16.0"
requires "illwill >= 0.2.0"
