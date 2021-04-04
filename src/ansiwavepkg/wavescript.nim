import unicode, tables, strutils, paramidi/constants
import json

type
  CommandText* = object
    text*: string
    line*: int
  FormKind = enum
    Whitespace, Symbol, Operator, Number, Command,
  Form = object
    case kind: FormKind
    of Whitespace:
      discard
    of Symbol, Operator, Number:
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

proc `$`(form: Form): string =
  case form.kind:
  of Whitespace:
    ""
  of Symbol, Operator, Number:
    form.name
  of Command:
    form.tree.name

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
    Instrument, Attribute, Length, LengthWithNumerator, Concurrent,

proc makeCommands(): Table[string, tuple[argc: int, kind: CommandKind]] =
  for inst in constants.instruments[1 ..< constants.instruments.len]:
    result["/" & inst] = (argc: -1, kind: Instrument)
  for length in [2, 4, 8]:
    result["/" & $length] = (argc: 0, kind: Length)
  result["/length"] = (argc: 1, kind: Attribute)
  result["/octave"] = (argc: 1, kind: Attribute)
  result["/tempo"] = (argc: 1, kind: Attribute)
  result["/"] = (argc: 2, kind: LengthWithNumerator)
  result["&"] = (argc: 2, kind: Concurrent)

const
  symbolChars = {'a'..'z', '#'}
  operatorChars = {'&', '/', '-', '+'}
  numberChars = {'0'..'9'}
  invalidChars = {'A'..'Z', '~', '`', '!', '@', '$', '%', '^', '*', '(', ')', '{', '}',
                  '[', ']', '_', '=', ':', ';', '<', '>', '.', ',', '"', '\'', '|', '\\', '?'}
  commands = makeCommands()

proc parse*(command: CommandText): CommandTree =
  var
    forms: seq[Form]
    form = Form(kind: Whitespace)
  proc flush() =
    forms.add(form)
    form = Form(kind: Whitespace)
  for ch in runes(command.text):
    let c = ch.toUTF8[0]
    case form.kind:
    of Whitespace:
      if operatorChars.contains(c):
        form = Form(kind: Operator, name: $c)
      elif symbolChars.contains(c) or invalidChars.contains(c):
        form = Form(kind: Symbol, name: $c)
      elif numberChars.contains(c):
        form = Form(kind: Number, name: $c)
    of Symbol, Operator, Number:
      if form.name == "/" and c == '/': # this is a comment, so ignore everything else
        form = Form(kind: Whitespace)
        break
      elif operatorChars.contains(c):
        if form.kind == Operator:
          form.name &= $c
        else:
          flush()
          form = Form(kind: Operator, name: $c)
      elif symbolChars.contains(c) or invalidChars.contains(c) or numberChars.contains(c):
        if form.kind == Operator:
          flush()
          if numberChars.contains(c):
            form = Form(kind: Number, name: $c)
          else:
            form = Form(kind: Symbol, name: $c)
        else:
          form.name &= $c
      else:
        flush()
        flush() # second flush to add the whitespace
    of Command:
      discard
  flush()
  # do some error checking
  for form in forms:
    if form.kind in {Symbol, Number}:
      let invalidIdx = strutils.find(form.name, invalidChars)
      if invalidIdx >= 0:
        return CommandTree(kind: Error, message: "$1 has an invalid character: $2".format(form.name, form.name[invalidIdx]))
      if form.kind == Number:
        let symbolIdx = strutils.find(form.name, symbolChars)
        if symbolIdx >= 0:
          return CommandTree(kind: Error, message: "$1 may not contain $2 because it is a number".format(form.name, form.name[symbolIdx]))
  # merge operators with symbols
  var
    newForms: seq[Form]
    i = 0
  while i < forms.len:
    # if there is whitespace on the left and not on the right
    if forms[i].kind == Operator and
        (i == 0 or forms[i-1].kind == Whitespace) and
        (i != forms.len - 1 and forms[i+1].kind in {Symbol, Number}):
      if forms[i].name != "/":
        return CommandTree(kind: Error, message: "Either remove the space before $1 or add a space after".format(forms[i].name))
      else:
        newForms.add(Form(kind: Symbol, name: forms[i].name & forms[i+1].name))
        i += 2
    # + and - with a symbol on the left and a symbol/number on the right should form a single symbol
    elif forms[i].kind == Operator and
        (forms[i].name == "+" or forms[i].name == "-") and
        (i > 0 and forms[i-1].kind == Symbol) and
        (i != forms.len - 1 and forms[i+1].kind in {Symbol, Number}):
      let lastItem = newForms.pop()
      newForms.add(Form(kind: Symbol, name: lastItem.name & forms[i].name & forms[i+1].name))
      i += 2
    elif forms[i].kind == Operator and
        (i == 0 or forms[i-1].kind in {Symbol, Number}) and
        (i != forms.len - 1 and forms[i+1].kind == Whitespace):
      return CommandTree(kind: Error, message: "Either remove the space after $1 or add a space before".format(forms[i].name))
    else:
      if forms[i].kind != Whitespace:
        newForms.add(forms[i])
      i.inc
  forms = newForms
  # group operators with their operands
  newForms = @[]
  i = 0
  while i < forms.len:
    if forms[i].kind == Operator:
      if i == 0 or i == forms.len - 1:
        return CommandTree(kind: Error, message: "$1 is not in a valid place".format(forms[i].name))
      elif not {Symbol, Number, Command}.contains(forms[i-1].kind) or not {Symbol, Number, Command}.contains(forms[i+1].kind):
        return CommandTree(kind: Error, message: "$1 must be surrounded by valid operands".format(forms[i].name))
      else:
        let lastItem = newForms.pop()
        newForms.add(Form(kind: Command, tree: CommandTree(kind: Valid, name: forms[i].name, args: @[lastItem, forms[i+1]])))
        i += 2
    else:
      newForms.add(forms[i])
      i.inc
  forms = newForms
  # create a hierarchical tree of commands
  proc getNextCommand(head: Form, forms: var seq[Form]): CommandTree =
    if head.kind == Command:
      return head.tree
    result = CommandTree(kind: Valid, name: head.name)
    if commands.contains(head.name):
      let (argc, kind) = commands[head.name]
      var argcFound = 0
      while forms.len > 0:
        if argc >= 0 and argcFound == argc:
          break
        let form = forms[0]
        forms = forms[1 ..< forms.len]
        if form.kind == Symbol and form.name[0] == '/':
          let cmd = getNextCommand(form, forms)
          if cmd.kind == Valid:
            result.args.add(Form(kind: Command, tree: cmd))
          else:
            return cmd
        else:
          result.args.add(form)
        argcFound.inc
      if argcFound < argc:
        return CommandTree(kind: Error, message: "$1 expects $2 arguments, but only $3 given".format($head, argc, argcFound))
    else:
      return CommandTree(kind: Error, message: "Command not found: $1".format(head.name))
  let head = forms[0]
  forms = forms[1 ..< forms.len]
  result = getNextCommand(head, forms)
  if result.kind == Valid and forms.len > 0:
    var extraInput = ""
    for form in forms:
      extraInput &= $form & " "
    result = CommandTree(kind: Error, message: "Extra input: $1".format(extraInput))

proc formToJson(form: Form): JsonNode =
  case form.kind:
  of Whitespace, Operator:
    raise newException(Exception, $form.kind & " cannot be converted to JSON")
  of Symbol:
    result = JsonNode(kind: JString, str: form.name)
  of Number:
    result = JsonNode(kind: JInt, num: strutils.parseBiggestInt(form.name))
  of Command:
    if not commands.contains(form.tree.name):
      raise newException(Exception, "Command not found: " & form.tree.name)
    let cmd = commands[form.tree.name]
    case cmd.kind:
    of Instrument:
      result = instrumentToJson(form.tree.name, form.tree.args)
    of Attribute:
      result = attributeToJson(form.tree.name, form.tree.args)
    of Length:
      result = JsonNode(kind: JFloat, fnum: 1 / strutils.parseInt(form.tree.name[1 ..< form.tree.name.len]))
    of LengthWithNumerator:
      if form.tree.args[0].kind != Number or form.tree.args[1].kind != Number:
        raise newException(Exception, "Only numbers can be divided")
      result = JsonNode(kind: JFloat, fnum: strutils.parseInt(form.tree.args[0].name) / strutils.parseInt(form.tree.args[1].name))
    of Concurrent:
      result = %*[{"mode": "concurrent"}, form.tree.args[0].formToJson, form.tree.args[1].formToJson]

proc toJson*(tree: CommandTree): JsonNode =
  result = formToJson(Form(kind: Command, tree: tree))
  # add a quarter note rest to prevent it from ending abruptly
  result.elems.add(JsonNode(kind: JFloat, fnum: 1/4))
  result.elems.add(JsonNode(kind: JString, str: "r"))

