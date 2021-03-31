import unittest
import ansiwave

test "Dedupe codes":
  const text = "\e[31m\e[32m\e[41mHello, world!\e[31m"
  let newText = text.dedupeCodes
  check newText == "\e[32;41mHello, world!\e[31m"
