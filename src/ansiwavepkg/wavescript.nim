import unicode, sequtils

type
  Command = object
    text: string
    line, columnStart, columnEnd: int

const
  slash = "/".runeAt(0)
  newline = "\n".runeAt(0)

proc parseCommands*(text: string): seq[Command] =
  var
    i = 0
    line = 0
    column = 0
    match: seq[Rune]
    command = false
  proc flush(res: var seq[Command]) =
    if match.len > 0:
      let columnStart = column
      column += match.len
      if match[0] == slash:
        res.add(Command(text: $match, line: line, columnStart: columnStart, columnEnd: column))
      match = @[]
  for ch in runes(text):
    if ch == newline:
      flush(result)
      line += 1
      column = 0
      command = false
    else:
      if ch == slash and not command:
        flush(result)
        command = true
      match.add(ch)
  flush(result)

