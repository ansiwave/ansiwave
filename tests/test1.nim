import unittest
import ansiwave
import re

test "Dedupe codes":
  const text = "\e[31m\e[32m\e[41;42;43mHello, world!\e[31m"
  let newText = text.dedupeCodes
  check newText.replace(re"\e", "e") == "e[32;43mHello, world!e[31m"
