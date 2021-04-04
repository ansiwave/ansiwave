import unicode, tables, strutils, paramidi/constants
import json

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

proc parse*(lines: seq[string]): seq[CommandText] =
  for i in 0 ..< lines.len:
    let line = lines[i]
    if line.len > 1:
      if line[0] == '/' and line[1] != '/': # don't add if it is a comment
        result.add(CommandText(text: line, line: i))

proc formToJson(form: Form): JsonNode

proc instrumentToJson(name: string, args: seq[Form]): JsonNode =
  result = JsonNode(kind: JArray)
  result.elems.add(JsonNode(kind: JString, str: name[1 ..< name.len]))
  for arg in args:
    result.elems.add(formToJson(arg))

proc attributeToJson(name: string, args: seq[Form]): JsonNode =
  result = JsonNode(kind: JObject)
  assert args.len == 1
  result.fields[name[1 ..< name.len]] = args[0].formToJson

type
  CommandKind = enum
    Instrument, Attribute,

proc makeCommands(): Table[string, tuple[argc: int, kind: CommandKind]] =
  for inst in constants.instruments[1 ..< constants.instruments.len]:
    result["/" & inst] = (argc: -1, kind: Instrument)
  result["/length"] = (argc: 1, kind: Attribute)
  result["/octave"] = (argc: 1, kind: Attribute)
  result["/mode"] = (argc: 1, kind: Attribute)
  result["/tempo"] = (argc: 1, kind: Attribute)

const
  symbolChars = {'a'..'z', 'A'..'Z', '_', '#'}
  numberChars = {'0'..'9'}
  commands = makeCommands()

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
      let (argc, kind) = commands[head.name]
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

proc formToJson(form: Form): JsonNode =
  case form.kind:
  of Whitespace:
    raise newException(Exception, "Whitespace cannot be converted to JSON")
  of Symbol:
    result = JsonNode(kind: JString, str: form.name)
  of Number:
    result = JsonNode(kind: JInt, num: strutils.parseBiggestInt(form.name))
  of Command:
    let cmd = commands[form.tree.name]
    case cmd.kind:
    of Instrument:
      result = instrumentToJson(form.tree.name, form.tree.args)
    of Attribute:
      result = attributeToJson(form.tree.name, form.tree.args)

proc toJson*(tree: CommandTree): JsonNode =
  result = formToJson(Form(kind: Command, tree: tree))
  # add a quarter note rest to prevent it from ending abruptly
  result.elems.add(JsonNode(kind: JFloat, fnum: 1/4))
  result.elems.add(JsonNode(kind: JString, str: "r"))

