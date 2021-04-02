import unicode

type
  TokenKind* = enum
    Newline, Whitespace, Command
  Token* = object
    text: string
    kind*: TokenKind
    line, columnStart, columnEnd: int

const
  slash = "/".runeAt(0)
  newline = "\n".runeAt(0)

proc tokenize*(text: string): seq[Token] =
  var
    i = 0
    line = 0
    column = 0
    match: seq[Rune]
    command = false
  proc flush(res: var seq[Token]) =
    if match.len > 0:
      let columnStart = column
      column += match.len
      if match[0] == slash:
        res.add(Token(text: $match, kind: Command, line: line, columnStart: columnStart, columnEnd: column))
      else:
        res.add(Token(text: $match, kind: Whitespace, line: line, columnStart: columnStart, columnEnd: column))
      match = @[]
  for ch in runes(text):
    if ch == newline:
      flush(result)
      result.add(Token(text: $newline, kind: Newline, line: line, columnStart: column, columnEnd: column + 1))
      line += 1
      column = 0
      command = false
    else:
      if ch == slash and not command:
        flush(result)
        command = true
      match.add(ch)
  flush(result)

