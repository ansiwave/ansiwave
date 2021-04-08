import unicode, tables, paramidi/constants
from strutils import format
import json, sets

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
    line*: int
    skip*: bool

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
    Instrument, Attribute, Length, LengthWithNumerator,
    Concurrent, ConcurrentLines,

type
  CommandMetadata = tuple[argc: int, kind: CommandKind]

proc initCommands(): Table[string, CommandMetadata] =
  for inst in constants.instruments:
    result["/" & inst] = (argc: -1, kind: Instrument)
  result["/length"] = (argc: 1, kind: Attribute)
  result["/octave"] = (argc: 1, kind: Attribute)
  result["/tempo"] = (argc: 1, kind: Attribute)
  result["/"] = (argc: 2, kind: LengthWithNumerator)
  result[","] = (argc: 2, kind: Concurrent)
  result["/,"] = (argc: 0, kind: ConcurrentLines)

proc toStr(form: Form): string =
  case form.kind:
  of Whitespace:
    ""
  of Symbol, Operator, Number:
    form.name
  of Command:
    form.tree.name

const
  symbolChars = {'a'..'z', '#'}
  operatorChars = {'/', '-', '+'}
  operatorSingleChars = {','} # operator chars that can only exist on their own
  numberChars = {'0'..'9'}
  invalidChars = {'A'..'Z', '~', '`', '!', '@', '$', '%', '^', '&', '*', '(', ')', '{', '}',
                  '[', ']', '_', '=', ':', ';', '<', '>', '.', '"', '\'', '|', '\\', '?'}
  whitespaceChars = {' '}
  operatorCommands = ["/,"].toHashSet
  commands = initCommands()

proc getCommand(meta: var CommandMetadata, name: string): bool =
  if commands.contains(name):
    meta = commands[name]
  else:
    try:
      discard strutils.parseInt(name[1 ..< name.len])
      meta = (argc: 0, kind: Length)
    except:
      return false
  true

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
      elif operatorSingleChars.contains(c):
        form = Form(kind: Operator, name: $c)
        flush()
      elif symbolChars.contains(c) or invalidChars.contains(c):
        form = Form(kind: Symbol, name: $c)
      elif numberChars.contains(c):
        form = Form(kind: Number, name: $c)
    of Symbol, Operator, Number:
      # this is a comment, so ignore everything else
      if form.name == "/" and c == '/':
        form = Form(kind: Whitespace)
        break
      elif operatorChars.contains(c):
        if form.kind == Operator:
          form.name &= $c
        else:
          flush()
          form = Form(kind: Operator, name: $c)
      elif operatorSingleChars.contains(c):
        flush()
        form = Form(kind: Operator, name: $c)
        flush()
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
        if whitespaceChars.contains(c):
          flush() # second flush to add the whitespace
    of Command:
      discard
  flush()
  # do some error checking
  for form in forms:
    if form.kind in {Symbol, Number}:
      let invalidIdx = strutils.find(form.name, invalidChars)
      if invalidIdx >= 0:
        return CommandTree(kind: Error, line: command.line, message: "$1 has an invalid character: $2".format(form.name, form.name[invalidIdx]))
      if form.kind == Number:
        let symbolIdx = strutils.find(form.name, symbolChars)
        if symbolIdx >= 0:
          return CommandTree(kind: Error, line: command.line, message: "$1 may not contain $2 because it is a number".format(form.name, form.name[symbolIdx]))
  # merge operators with adjacent tokens in some cases
  var
    newForms: seq[Form]
    i = 0
  while i < forms.len:
    # / with whitespace on the left and symbol/number/operator on the right should form a single symbol
    if forms[i].kind == Operator and
        forms[i].name == "/" and
        (i == 0 or forms[i-1].kind == Whitespace) and
        (i != forms.len - 1 and forms[i+1].kind in {Symbol, Number, Operator}):
      newForms.add(Form(kind: Symbol, name: forms[i].name & forms[i+1].name))
      i += 2
    # + and - with whitespace on the left and number on the right should form a single number
    elif forms[i].kind == Operator and
        (forms[i].name == "+" or forms[i].name == "-") and
        (i == 0 or forms[i-1].kind == Whitespace) and
        (i != forms.len - 1 and forms[i+1].kind == Number):
      newForms.add(Form(kind: Number, name: forms[i].name & forms[i+1].name))
      i += 2
    # + and - with whitespace on the left and symbol on the right should form a command
    elif forms[i].kind == Operator and
        (forms[i].name == "+" or forms[i].name == "-") and
        (i == 0 or forms[i-1].kind == Whitespace) and
        (i != forms.len - 1 and forms[i+1].kind == Symbol):
      newForms.add(Form(kind: Command, tree: CommandTree(kind: Valid, line: command.line, name: forms[i].name, args: @[forms[i+1]])))
      i += 2
    # + and - with a symbol on the left should form a single symbol (including symbol/number on the right if it exists)
    elif forms[i].kind == Operator and
        (forms[i].name == "+" or forms[i].name == "-") and
        (i > 0 and forms[i-1].kind == Symbol):
      let lastItem = newForms.pop()
      if i != forms.len - 1 and forms[i+1].kind in {Symbol, Number}:
        newForms.add(Form(kind: Symbol, name: lastItem.name & forms[i].name & forms[i+1].name))
        i += 2
      else:
        newForms.add(Form(kind: Symbol, name: lastItem.name & forms[i].name))
        i.inc
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
        return CommandTree(kind: Error, line: command.line, message: "$1 is not in a valid place".format(forms[i].name))
      elif not {Symbol, Number, Command}.contains(forms[i-1].kind) or not {Symbol, Number, Command}.contains(forms[i+1].kind):
        return CommandTree(kind: Error, line: command.line, message: "$1 must be surrounded by valid operands".format(forms[i].name))
      else:
        let lastItem = newForms.pop()
        newForms.add(Form(kind: Command, tree: CommandTree(kind: Valid, line: command.line, name: forms[i].name, args: @[lastItem, forms[i+1]])))
        i += 2
    else:
      newForms.add(forms[i])
      i.inc
  forms = newForms
  # create a hierarchical tree of commands
  proc getNextCommand(head: Form, forms: var seq[Form]): CommandTree =
    if head.kind == Command:
      return CommandTree(kind: Error, line: command.line, message: "$1 is not in a valid place".format(head.tree.name))
    result = CommandTree(kind: Valid, line: command.line, name: head.name)
    var cmd: CommandMetadata
    if getCommand(cmd, head.name):
      let (argc, kind) = cmd
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
        return CommandTree(kind: Error, line: command.line, message: "$1 expects $2 arguments, but only $3 given".format(head.toStr, argc, argcFound))
    else:
      return CommandTree(kind: Error, line: command.line, message: "Command not found: $1".format(head.name))
  let head = forms[0]
  forms = forms[1 ..< forms.len]
  result = getNextCommand(head, forms)
  # error if there is any extra input
  if result.kind == Valid and forms.len > 0:
    var extraInput = ""
    for form in forms:
      extraInput &= form.toStr & " "
    result = CommandTree(kind: Error, line: command.line, message: "Extra input: $1".format(extraInput))

proc parseOperatorCommands*(trees: seq[CommandTree]): seq[CommandTree] =
  var
    i = 0
    treesMut = trees
  while i < treesMut.len:
    var tree = treesMut[i]
    if tree.kind == Valid and operatorCommands.contains(tree.name):
      var lastNonSkippedLine = i-1
      while lastNonSkippedLine >= 0:
        if not treesMut[lastNonSkippedLine].skip:
          break
        lastNonSkippedLine.dec
      if i == 0 or i == treesMut.len - 1 or
          lastNonSkippedLine == -1 or
          treesMut[lastNonSkippedLine].kind == Error or
          treesMut[i+1].kind == Error:
        result.add(CommandTree(kind: Error, line: tree.line, message: "$1 must have a valid command above and below it".format(tree.name)))
        i.inc
      else:
        var prevLine = result[lastNonSkippedLine]
        prevLine.skip = true # skip prev line when playing all lines
        var nextLine = treesMut[i+1]
        nextLine.skip = true # skip next line when playing all lines
        result[lastNonSkippedLine] = prevLine
        treesMut[i+1] = nextLine
        tree.args.add(Form(kind: Command, tree: prevLine))
        tree.args.add(Form(kind: Command, tree: nextLine))
        result.add(tree)
        result.add(nextLine)
        i += 2
    else:
      result.add(tree)
      i.inc

proc formToJson(form: Form): JsonNode =
  case form.kind:
  of Whitespace, Operator:
    raise newException(Exception, $form.kind & " cannot be converted to JSON")
  of Symbol:
    result = JsonNode(kind: JString, str: form.name)
  of Number:
    result = JsonNode(kind: JInt, num: strutils.parseBiggestInt(form.name))
  of Command:
    var cmd: CommandMetadata
    if not getCommand(cmd, form.tree.name):
      raise newException(Exception, "Command not found: " & form.tree.name)
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
    of ConcurrentLines:
      if form.tree.args.len != 2:
        raise newException(Exception, "$1 is not in a valid place".format(form.tree.name))
      result = %*[{"mode": "concurrent"}, form.tree.args[0].formToJson, form.tree.args[1].formToJson]

proc toJson*(tree: CommandTree): JsonNode =
  formToJson(Form(kind: Command, tree: tree))

