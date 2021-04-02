import unicode, tables, strutils

type
  CommandText* = object
    text*: string
    line*: int
  FormKind = enum
    Whitespace, Symbol, Number, Command,
  Form = object
    case kind: FormKind
    of Whitespace:
      discard
    of Symbol, Number:
      name: string
    of Command:
      tree: CommandTree
  CommandTreeKind* = enum
    Valid, Error,
  CommandTree* = object
    case kind*: CommandTreeKind
    of Valid:
      name*: string
      args*: seq[Form]
    of Error:
      message*: string

const
  slash = "/".runeAt(0)
  newline = "\n".runeAt(0)

proc parse*(text: string): seq[CommandText] =
  var
    i = 0
    line = 0
    match: seq[Rune]
  proc flush(res: var seq[CommandText]) =
    if match.len > 1:
      if match[0] == slash and match[1] != slash: # don't add if it is a comment
        res.add(CommandText(text: $match, line: line))
      match = @[]
  for ch in runes(text):
    if ch == newline:
      flush(result)
      line += 1
    else:
      match.add(ch)
  flush(result)

const
  symbolChars = {'a'..'z', 'A'..'Z', '_', '#'}
  numberChars = {'0'..'9'}
  commands = {
    "/piano": (argc: -1),
    "/octave": (argc: 1),
  }.toTable

proc parse*(command: CommandText): CommandTree =
  var
    forms: seq[Form]
    form = Form(kind: Whitespace)
  proc flush() =
    if form.kind == Symbol or form.kind == Number:
      forms.add(form)
      form = Form(kind: Whitespace)
  for ch in runes(command.text):
    let c = ch.toUTF8[0]
    case form.kind:
    of Whitespace:
      if symbolChars.contains(c) or c == '/':
        form = Form(kind: Symbol, name: $c)
      elif numberChars.contains(c):
        form = Form(kind: Number, name: $c)
    of Symbol:
      if c == '/':
        if form.name == "/": # this is a comment, so ignore everything else
          form = Form(kind: Whitespace)
          break
        else:
          return CommandTree(kind: Error, message: "Misplaced / character")
      elif symbolChars.contains(c) or numberChars.contains(c):
        form.name &= $c
      else:
        flush()
    of Number:
      if numberChars.contains(c):
        form.name &= $c
      else:
        flush()
    of Command:
      discard
  flush()
  proc getNextCommand(head: Form, forms: var seq[Form]): CommandTree =
    result = CommandTree(kind: Valid, name: head.name)
    if commands.contains(head.name):
      let (argc) = commands[head.name]
      var argcFound = 0
      while forms.len > 0:
        if argc >= 0 and argcFound == argc:
          break
        let form = forms[0]
        forms = forms[1 ..< forms.len]
        if form.name[0] == '/':
          let cmd = getNextCommand(form, forms)
          if cmd.kind == Valid:
            result.args.add(Form(kind: Command, tree: cmd))
          else:
            return cmd
        else:
          result.args.add(form)
        argcFound.inc
      if argcFound < argc:
        return CommandTree(kind: Error, message: "$1 expects $2 arguments, but only $3 given".format(head.name, argc, argcFound))
    else:
      return CommandTree(kind: Error, message: "Command not found: $1".format(head.name))
  let head = forms[0]
  forms = forms[1 ..< forms.len]
  result = getNextCommand(head, forms)
  if result.kind == Valid and forms.len > 0:
    var extraInput = ""
    for form in forms:
      extraInput &= form.name & " "
    result = CommandTree(kind: Error, message: "Extra input: $1".format(extraInput))
