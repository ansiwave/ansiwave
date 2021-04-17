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
    Valid, Error, Discard,
  CommandTree* = object
    case kind*: CommandTreeKind
    of Valid:
      name*: string
      args*: seq[Form]
    of Error, Discard:
      message*: string
    line*: int
    skip*: bool
  CommandKind = enum
    Play, Instrument, PlayInstrument, Attribute, Length, LengthWithNumerator,
    Concurrent, ConcurrentLines, Let,
  CommandMetadata = tuple[argc: int, kind: CommandKind]
  Commands = Table[string, CommandMetadata]
  Context* = object
    commands: Commands
    variables: Table[string, seq[Form]]

proc parse*(lines: seq[string]): seq[CommandText] =
  for i in 0 ..< lines.len:
    let line = lines[i]
    if line.len > 1:
      if line[0] == '/' and line[1] != '/': # don't add if it is a comment
        result.add(CommandText(text: line, line: i))

proc toJson(form: Form): JsonNode

proc instrumentToJson(name: string, args: seq[Form]): JsonNode =
  result = JsonNode(kind: JArray)
  result.elems.add(JsonNode(kind: JString, str: name[1 ..< name.len]))
  for arg in args:
    result.elems.add(toJson(arg))

proc attributeToJson(name: string, args: seq[Form]): JsonNode =
  result = JsonNode(kind: JObject)
  assert args.len == 1
  result.fields[name[1 ..< name.len]] = toJson(args[0])

proc initCommands(): Table[string, CommandMetadata] =
  for inst in constants.instruments:
    result["/" & inst] = (argc: -1, kind: PlayInstrument)
  result["/length"] = (argc: 1, kind: Attribute)
  result["/octave"] = (argc: 1, kind: Attribute)
  result["/tempo"] = (argc: 1, kind: Attribute)
  result["/"] = (argc: 2, kind: LengthWithNumerator)
  result[","] = (argc: 2, kind: Concurrent)
  result["/,"] = (argc: 0, kind: ConcurrentLines)
  result["/let"] = (argc: -1, kind: Let)
  result["/play"] = (argc: -1, kind: Play)
  result["/instrument"] = (argc: 1, kind: Instrument)

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
  whitespaceChars* = [" ", "█", "▓", "▒", "░", "▀", "▄", "▌", "▐"].toHashSet
  operatorCommands = ["/,"].toHashSet
  commands = initCommands()

proc initContext*(): Context =
  result.commands = commands

proc getCommand(meta: var CommandMetadata, name: string): bool =
  if name in commands:
    meta = commands[name]
  else:
    try:
      discard strutils.parseInt(name[1 ..< name.len])
      meta = (argc: 0, kind: Length)
    except:
      return false
  true

proc toCommandTree(context: var Context, forms: seq[Form], command: CommandText): CommandTree =
  # create a hierarchical tree of commands
  proc getNextCommand(context: var Context, head: Form, forms: var seq[Form], topLevel: bool): CommandTree =
    if head.kind == Command:
      return CommandTree(kind: Error, line: command.line, message: "$1 is not in a valid place".format(head.tree.name))
    result = CommandTree(kind: Valid, line: command.line, name: head.name)
    var cmd: CommandMetadata
    if getCommand(cmd, head.name):
      let (argc, kind) = cmd
      if kind == Let:
        if not topLevel:
          return CommandTree(kind: Error, line: command.line, message: "$1 cannot be placed within another command".format(head.name))
        elif forms.len < 2:
          return CommandTree(kind: Error, line: command.line, message: "$1 does not have enough input".format(head.name))
        elif forms[0].kind != Symbol or forms[0].name[0] == '/':
          return CommandTree(kind: Error, line: command.line, message: "$1 must have a symbol as its first input".format(head.name))
        else:
          let name = "/" & forms[0].name
          if name in commands or name in context.variables:
            return CommandTree(kind: Error, line: command.line, message: "$1 already was defined".format(name))
          context.variables[name] = forms[1 ..< forms.len]
          result.skip = true
      var argcFound = 0
      while forms.len > 0:
        if argc >= 0 and argcFound == argc:
          break
        let form = forms[0]
        forms = forms[1 ..< forms.len]
        if form.kind == Symbol and form.name[0] == '/':
          let cmd = getNextCommand(context, form, forms, false)
          case cmd.kind:
          of Valid:
            result.args.add(Form(kind: Command, tree: cmd))
          of Error:
            return cmd
          of Discard:
            discard
        else:
          result.args.add(form)
        argcFound.inc
      if argcFound < argc:
        return CommandTree(kind: Error, line: command.line, message: "$1 expects $2 arguments, but only $3 given".format(head.toStr, argc, argcFound))
    elif head.name in context.variables:
      forms = context.variables[head.name] & forms
      return CommandTree(kind: Discard, line: command.line, message: "$1 must be placed within another command".format(head.name))
    else:
      return CommandTree(kind: Error, line: command.line, message: "Command not found: $1".format(head.name))
  let head = forms[0]
  var rest = forms[1 ..< forms.len]
  result = getNextCommand(context, head, rest, true)
  # error if there is any extra input
  if result.kind == Valid and rest.len > 0:
    var extraInput = ""
    for form in rest:
      extraInput &= form.toStr & " "
    result = CommandTree(kind: Error, line: command.line, message: "Extra input: $1".format(extraInput))

proc parse*(context: var Context, command: CommandText): CommandTree =
  var
    forms: seq[Form]
    form = Form(kind: Whitespace)
  proc flush() =
    forms.add(form)
    form = Form(kind: Whitespace)
  for ch in runes(command.text):
    let
      s = ch.toUTF8
      c = s[0]
    case form.kind:
    of Whitespace:
      if c in operatorChars:
        form = Form(kind: Operator, name: $c)
      elif c in operatorSingleChars:
        form = Form(kind: Operator, name: $c)
        flush()
      elif c in symbolChars or c in invalidChars:
        form = Form(kind: Symbol, name: $c)
      elif c in numberChars:
        form = Form(kind: Number, name: $c)
    of Symbol, Operator, Number:
      # this is a comment, so ignore everything else
      if form.name == "/" and c == '/':
        form = Form(kind: Whitespace)
        break
      elif c in operatorChars:
        if form.kind == Operator:
          form.name &= $c
        else:
          flush()
          form = Form(kind: Operator, name: $c)
      elif c in operatorSingleChars:
        flush()
        form = Form(kind: Operator, name: $c)
        flush()
      elif c in symbolChars or c in invalidChars or c in numberChars:
        if form.kind == Operator:
          flush()
          if c in numberChars:
            form = Form(kind: Number, name: $c)
          else:
            form = Form(kind: Symbol, name: $c)
        else:
          form.name &= $c
      else:
        flush()
        if s in whitespaceChars:
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
    # / with whitespace or comma on the left and symbol/number/operator on the right should form a single symbol
    if forms[i].kind == Operator and
        forms[i].name == "/" and
        (i == 0 or forms[i-1].kind == Whitespace or (forms[i-1].kind == Operator and forms[i-1].name == ",")) and
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
        (i > 0 and newForms.len > 0 and newForms[newForms.len-1].kind == Symbol):
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
      elif forms[i-1].kind notin {Symbol, Number, Command} or forms[i+1].kind notin {Symbol, Number, Command}:
        return CommandTree(kind: Error, line: command.line, message: "$1 must be surrounded by valid operands".format(forms[i].name))
      else:
        let lastItem = newForms.pop()
        newForms.add(Form(kind: Command, tree: CommandTree(kind: Valid, line: command.line, name: forms[i].name, args: @[lastItem, forms[i+1]])))
        i += 2
    else:
      newForms.add(forms[i])
      i.inc
  forms = newForms
  toCommandTree(context, forms, command)

proc parseOperatorCommands*(trees: seq[CommandTree]): seq[CommandTree] =
  var
    i = 0
    treesMut = trees
  while i < treesMut.len:
    var tree = treesMut[i]
    if tree.kind == Valid and tree.name in operatorCommands:
      var lastNonSkippedLine = i-1
      while lastNonSkippedLine >= 0:
        if not result[lastNonSkippedLine].skip:
          break
        lastNonSkippedLine.dec
      if i == 0 or i == treesMut.len - 1 or
          lastNonSkippedLine == -1 or
          result[lastNonSkippedLine].kind == Error or
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

proc toJson(form: Form): JsonNode =
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
    of Play:
      result = JsonNode(kind: JArray)
      for arg in form.tree.args:
        result.elems.add(toJson(arg))
    of Instrument:
      if form.tree.args[0].kind != Symbol:
        raise newException(Exception, "Instrument names must be symbols")
      result = JsonNode(kind: JString, str: form.tree.args[0].name)
    of PlayInstrument:
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
      result = %*[{"mode": "concurrent"}, form.tree.args[0].toJson, form.tree.args[1].toJson]
    of ConcurrentLines:
      if form.tree.args.len != 2:
        raise newException(Exception, "$1 is not in a valid place".format(form.tree.name))
      result = %*[{"mode": "concurrent"}, form.tree.args[0].toJson, form.tree.args[1].toJson]
    of Let:
      result = JsonNode(kind: JArray)
      for arg in form.tree.args[1 ..< form.tree.args.len]:
        result.elems.add(toJson(arg))

proc toJson*(tree: CommandTree): JsonNode =
  toJson(Form(kind: Command, tree: tree))

