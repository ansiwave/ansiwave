# Package

version       = "0.1.0"
author        = "oakes"
description   = "ANSI art + MIDI music"
license       = "Public Domain"
srcDir        = "src"
installExt    = @["nim", "ansiwave"]
bin           = @["ansiwave"]

task dev, "Run dev version":
  # this sets release mode because playing music
  # is unstable in debug builds for some reason
  exec "nimble -d:release run ansiwave tests/variables.ansiwave"

# Dependencies

requires "nim >= 1.4.4"
requires "pararules >= 0.17.0"
requires "paramidi >= 0.5.0"
requires "paramidi_soundfonts >= 0.2.0"
requires "parasound >= 0.2.0"
requires "illwill >= 0.2.0"
requires "zippy >= 0.5.5"
