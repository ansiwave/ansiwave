from illwave as iw import `[]`, `[]=`, `==`, TerminalBuffer
import tables, sets
import pararules
from pararules/engine import Session, Vars
import unicode
from os import nil
from strutils import format
from sequtils import nil
from sugar import nil
from times import nil
from wavecorepkg/wavescript import CommandTree
from ../midi import nil
from ../sound import nil
from ansiutils/codes import stripCodes
import ../constants
from paramidi import Context
from json import nil
from zippy import nil
from wavecorepkg/paths import nil
import streams
import json
from ../storage import nil
from ../post import RefStrings, ToWrappedTable, ToUnwrappedTable
from terminal import nil
from nimwave import nil
from nimwave/tui import nil
from nimwave/tui/termtools/runewidth import nil

type
  Id* = enum
    Global, TerminalWindow,
    Editor, Errors, Tutorial, Publish,
  Attr* = enum
    CursorX, CursorY, WrappedCursorX, WrappedCursorY, Cursor, WrappedCursor,
    AdjustedWrappedCursorX,
    ScrollX, ScrollY,
    X, Y, Width, Height,
    SelectedBuffer, Lines, WrappedLines, ToWrapped, ToUnwrapped,
    Editable, SelectedMode, SelectedBrightness,
    SelectedChar, SelectedFgColor, SelectedBgColor,
    Prompt, ValidCommands, InvalidCommands, Links,
    HintText, HintTime, UndoHistory, UndoIndex, InsertMode,
    LastEditTime, LastSaveTime, AllBuffers, Opts, MidiProgress,
  PromptKind = enum
    None, DeleteLine, StopPlaying,
  Snapshot = object
    lines: seq[ref string]
    cursorX: int
    cursorY: int
    time: float
  Snapshots = ref seq[Snapshot]
  RefCommands = ref seq[wavescript.CommandTree]
  Link = object
    icon: Rune
    callback: proc ()
    error: bool
  RefLinks = ref Table[int, Link]
  Options* = object
    input*: string
    output*: string
    args*: Table[string, string]
    bbsMode*: bool
    sig*: string
  Buffer = tuple
    id: int
    cursorX: int
    cursorY: int
    wrappedCursorX: int
    wrappedCursorY: int
    adjustedWrappedCursorX: int
    scrollX: int
    scrollY: int
    lines: RefStrings
    wrappedLines: RefStrings
    toWrapped: ToWrappedTable
    toUnwrapped: ToUnwrappedTable
    x: int
    y: int
    width: int
    height: int
    editable: bool
    mode: int
    brightness: int
    selectedChar: string
    selectedFgColor: string
    selectedBgColor: string
    prompt: PromptKind
    commands: RefCommands
    errors: RefCommands
    links: RefLinks
    undoHistory: Snapshots
    undoIndex: int
    insertMode: bool
    lastEditTime: float
    lastSaveTime: float
  BufferTable = ref Table[int, Buffer]
  MidiProgressType = ref object
    messageDisplayed: bool
    started: bool
    events: seq[paramidi.Event]
    lineTimes: seq[tuple[line: int, time: float]]
    time: tuple[start: float, stop: float]
    addrs: sound.Addrs
  XY = tuple[x: int, y: int]

schema Fact(Id, Attr):
  CursorX: int
  CursorY: int
  WrappedCursorX: int
  WrappedCursorY: int
  AdjustedWrappedCursorX: int
  Cursor: XY
  WrappedCursor: XY
  ScrollX: int
  ScrollY: int
  X: int
  Y: int
  Width: int
  Height: int
  SelectedBuffer: Id
  Lines: RefStrings
  WrappedLines: RefStrings
  ToWrapped: ToWrappedTable
  ToUnwrapped: ToUnwrappedTable
  Editable: bool
  SelectedMode: int
  SelectedBrightness: int
  SelectedChar: string
  SelectedFgColor: string
  SelectedBgColor: string
  Prompt: PromptKind
  ValidCommands: RefCommands
  InvalidCommands: RefCommands
  Links: RefLinks
  HintText: string
  HintTime: float
  UndoHistory: Snapshots
  UndoIndex: int
  InsertMode: bool
  LastEditTime: float
  LastSaveTime: float
  AllBuffers: BufferTable
  Opts: Options
  MidiProgress: MidiProgressType

const textWidth* = editorWidth + 2

proc play(session: var auto, events: seq[paramidi.Event], lineTimes: seq[tuple[line: int, time: float]]) =
  var progress: MidiProgressType
  new progress
  progress.events = events
  progress.lineTimes = lineTimes
  session.insert(Global, MidiProgress, progress)

proc setErrorLink(session: var auto, linksRef: RefLinks, cmdLine: int, errLine: int): Link =
  var sess = session
  let
    cb =
      proc () =
        sess.insert(Global, SelectedBuffer, Errors)
        sess.insert(Errors, CursorX, 0)
        sess.insert(Errors, CursorY, errLine)
    link = Link(icon: "!".runeAt(0), callback: cb, error: true)
  linksRef[cmdLine] = link
  link

proc setRuntimeError(session: var auto, cmdsRef: RefCommands, errsRef: RefCommands, linksRef: RefLinks, bufferId: int, line: int, message: string, goToError: bool = false) =
  var cmdIndex = -1
  for i in 0 ..< cmdsRef[].len:
    if cmdsRef[0].line == line:
      cmdIndex = i
      break
  if cmdIndex >= 0:
    cmdsRef[].delete(cmdIndex)
  var errIndex = -1
  for i in 0 ..< errsRef[].len:
    if errsRef[0].line == line:
      errIndex = i
      break
  if errIndex >= 0:
    errsRef[].delete(errIndex)
  let link = setErrorLink(session, linksRef, line, errsRef[].len)
  errsRef[].add(wavescript.CommandTree(kind: wavescript.Error, line: line, message: message))
  session.insert(bufferId, InvalidCommands, errsRef)
  if goToError:
    link.callback()

proc compileAndPlayAll(session: var auto, buffer: tuple) =
  var
    noErrors = true
    nodes = json.JsonNode(kind: json.JArray)
    lineTimes: seq[tuple[line: int, time: float]]
    midiContext = paramidi.initContext()
    lastTime = 0.0
  for cmd in buffer.commands[]:
    if cmd.kind != wavescript.Valid or cmd.skip:
      continue
    let
      res =
        try:
          let node = wavescript.toJson(cmd)
          nodes.elems.add(node)
          midi.compileScore(midiContext, node, false)
        except Exception as e:
          midi.CompileResult(kind: midi.Error, message: e.msg)
    case res.kind:
    of midi.Valid:
      lineTimes.add((cmd.line, lastTime))
      lastTime = midiContext.seconds
    of midi.Error:
      setRuntimeError(session, buffer.commands, buffer.errors, buffer.links, buffer.id, cmd.line, res.message, true)
      noErrors = false
      break
  if noErrors:
    midiContext = paramidi.initContext()
    let res =
      try:
        midi.compileScore(midiContext, nodes, true)
      except Exception as e:
        midi.CompileResult(kind: midi.Error, message: e.msg)
    case res.kind:
    of midi.Valid:
      if res.events.len > 0:
        play(session, res.events, lineTimes)
    of midi.Error:
      discard

proc cursorChanged(session: var auto, id: int, cursorX: int, cursorY: int, lines: RefStrings): tuple[x: int, y: int] =
  result = (cursorX, cursorY)
  if lines[].len == 0:
    if cursorX != 0:
      result.x = 0
    if cursorY != 0:
      result.y = 0
    return
  if cursorY < 0:
    result.y = 0
  elif cursorY >= lines[].len:
    result.y = lines[].len - 1
  else:
    let lastCol = lines[cursorY][].stripCodes.runeLen
    if cursorX > lastCol:
      result.x = lastCol
    elif cursorX < 0:
      result.x = 0

proc unwrapLines(wrappedLines: RefStrings, toUnwrapped: ToUnwrappedTable): RefStrings =
  new result
  for wrappedLineNum in 0 ..< wrappedLines[].len:
    if toUnwrapped.hasKey(wrappedLineNum):
      let (lineNum, _, _) = toUnwrapped[wrappedLineNum]
      if result[].len > lineNum:
        post.set(result, lineNum, result[lineNum][] & wrappedLines[wrappedLineNum][])
      else:
        result[].add(wrappedLines[wrappedLineNum])
    else:
      result[].add(wrappedLines[wrappedLineNum])

proc removeWrappedLines(lines: var seq[ref string], toUnwrapped: ToUnwrappedTable) =
  var
    lineNums: HashSet[int]
    empty: ref string
  new empty
  for i in 0 ..< lines.len:
    let lineNum = toUnwrapped[i].lineNum
    if lineNum notin lineNums:
      lineNums.incl(lineNum)
    else:
      lines[i] = empty

# the wasm binary gets too big if we use staticRuleset,
# so make the emscripten version define rules the normal way
import macros
when defined(emscripten):
  type FactMatch = Table[string, Fact]
  macro defRuleset(arg: untyped): untyped =
    quote:
      let rules =
        ruleset:
          `arg`
      (initSession:
        proc (autoFire: bool = true): Session[Fact, FactMatch] =
          initSession(Fact, autoFire = autoFire)
       ,
       rules: rules)
else:
  macro defRuleset(arg: untyped): untyped =
    quote:
      staticRuleset(Fact, FactMatch):
        `arg`

let (initSession, rules*) =
  defRuleset:
    rule getGlobals(Fact):
      what:
        (Global, SelectedBuffer, selectedBuffer)
        (Global, HintText, hintText)
        (Global, HintTime, hintTime)
        (Global, AllBuffers, buffers)
        (Global, Opts, options)
        (Global, MidiProgress, midiProgress)
    rule getTerminalWindow(Fact):
      what:
        (TerminalWindow, Width, width)
        (TerminalWindow, Height, height)
    rule updateTerminalScrollX(Fact):
      what:
        (id, Width, bufferWidth)
        (id, WrappedCursorX, cursorX)
        (id, ScrollX, scrollX, then = false)
      cond:
        cursorX >= 0
      then:
        let scrollRight = scrollX + bufferWidth - 1
        if cursorX < scrollX:
          session.insert(id, ScrollX, cursorX)
        elif cursorX > scrollRight:
          session.insert(id, ScrollX, scrollX + (cursorX - scrollRight))
    rule updateTerminalScrollY(Fact):
      what:
        (id, Height, bufferHeight)
        (id, WrappedCursorY, cursorY)
        (id, WrappedLines, lines)
        (id, ScrollY, scrollY, then = false)
      cond:
        cursorY >= 0
      then:
        let scrollBottom = scrollY + bufferHeight - 1
        if cursorY < scrollY:
          session.insert(id, ScrollY, cursorY)
        elif cursorY > scrollBottom and cursorY < lines[].len:
          session.insert(id, ScrollY, scrollY + (cursorY - scrollBottom))
    rule parseCommands(Fact):
      what:
        (Global, Opts, options)
        (id, WrappedLines, lines)
        (id, ToUnwrapped, toUnwrapped)
      cond:
        id != Errors.ord
      then:
        var nonWrappedLines = lines[]
        removeWrappedLines(nonWrappedLines, toUnwrapped)
        let trees = post.linesToTrees(nonWrappedLines)
        var cmdsRef, errsRef: RefCommands
        var linksRef: RefLinks
        new cmdsRef
        new errsRef
        new linksRef
        var
          sess = session
          midiContext = paramidi.initContext()
        for tree in trees:
          case tree.kind:
          of wavescript.Valid:
            if tree.name in wavescript.stringCommands:
              let ch =
                case tree.name:
                of "/section": "§"
                else: "→"
              linksRef[tree.line] = Link(icon: ch.runeAt(0), callback: proc () = discard)
            else:
              # set the play button in the gutter to play the line
              let treeLocal = tree
              sugar.capture cmdsRef, errsRef, linksRef, id, treeLocal, midiContext:
                let cb =
                  proc () =
                    var ctx = midiContext
                    ctx.time = 0
                    new ctx.events
                    let res =
                      try:
                        midi.compileScore(ctx, wavescript.toJson(treeLocal), true)
                      except Exception as e:
                        midi.CompileResult(kind: midi.Error, message: e.msg)
                    case res.kind:
                    of midi.Valid:
                      play(sess, res.events, @[])
                    of midi.Error:
                      if id == Editor.ord:
                        setRuntimeError(sess, cmdsRef, errsRef, linksRef, id, treeLocal.line, res.message)
                linksRef[treeLocal.line] = Link(icon: "♫".runeAt(0), callback: cb)
              cmdsRef[].add(tree)
              # compile the line so the context object updates
              # this is important so attributes changed by previous lines
              # affect the play button
              try:
                discard paramidi.compile(midiContext, wavescript.toJson(tree))
              except:
                discard
          of wavescript.Error, wavescript.Discard:
            if id == Editor.ord:
              discard setErrorLink(sess, linksRef, tree.line, errsRef[].len)
              errsRef[].add(tree)
        session.insert(id, ValidCommands, cmdsRef)
        session.insert(id, InvalidCommands, errsRef)
        session.insert(id, Links, linksRef)
    rule updateErrors(Fact):
      what:
        (Editor, InvalidCommands, errors)
      then:
        var newLines: RefStrings
        var linksRef: RefLinks
        new newLines
        new linksRef
        for error in errors[]:
          var sess = session
          let line = error.line
          sugar.capture line:
            let cb =
              proc () =
                sess.insert(Global, SelectedBuffer, Editor)
                sess.insert(Editor, SelectedMode, 0) # force it to be write mode so the cursor is visible
                sess.insert(Editor, CursorY, line)
            linksRef[newLines[].len] = Link(icon: "!".runeAt(0), callback: cb, error: true)
          post.add(newLines, error.message)
        session.insert(Errors, Lines, newLines)
        session.insert(Errors, CursorX, 0)
        session.insert(Errors, CursorY, 0)
        session.insert(Errors, Links, linksRef)
    rule updateHistory(Fact):
      what:
        (id, Lines, lines)
        (id, CursorX, x)
        (id, CursorY, y)
        (id, UndoHistory, history, then = false)
        (id, UndoIndex, undoIndex, then = false)
      then:
        if undoIndex >= 0 and
            undoIndex < history[].len and
            history[undoIndex].lines == lines[]:
          # if only the cursor changed, update it in the undo history
          if history[undoIndex].cursorX != x or history[undoIndex].cursorY != y:
            history[undoIndex].cursorX = x
            history[undoIndex].cursorY = y
            session.insert(id, UndoHistory, history)
          return
        let
          currTime = times.epochTime()
          newIndex =
            # if there is a previous undo moment that occurred recently,
            # replace that instead of making a new moment
            if undoIndex > 0 and currTime - history[undoIndex].time <= undoDelay:
              undoIndex
            else:
              undoIndex + 1
        if history[].len == newIndex:
          history[].add(Snapshot(lines: lines[], cursorX: x, cursorY: y, time: currTime))
        elif history[].len > newIndex:
          history[] = history[0 .. newIndex]
          history[newIndex] = Snapshot(lines: lines[], cursorX: x, cursorY: y, time: currTime)
        session.insert(id, UndoHistory, history)
        if newIndex != undoIndex:
          session.insert(id, UndoIndex, newIndex)
    rule undoIndexChanged(Fact):
      what:
        (id, Lines, lines, then = false)
        (id, UndoIndex, undoIndex)
        (id, UndoHistory, history, then = false)
      cond:
        undoIndex >= 0
        undoIndex < history[].len
        history[undoIndex].lines != lines[]
      then:
        let moment = history[undoIndex]
        var newLines: RefStrings
        new newLines
        newLines[] = moment.lines
        session.insert(id, Lines, newLines)
        session.insert(id, CursorX, moment.cursorX)
        session.insert(id, CursorY, moment.cursorY)
    rule updateLastEditTime(Fact):
      what:
        (id, Lines, lines)
      then:
        session.insert(id, LastEditTime, times.epochTime())
    rule wrapLines(Fact):
      what:
        (id, Lines, lines)
      then:
        let (wrappedLines, toWrapped, toUnwrapped) = post.wrapLines(lines)
        session.insert(id, WrappedLines, wrappedLines)
        session.insert(id, ToWrapped, toWrapped)
        session.insert(id, ToUnwrapped, toUnwrapped)
    rule updateCursor(Fact):
      what:
        (id, CursorX, cursorX)
        (id, CursorY, cursorY)
      then:
        session.insert(id, Cursor, (cursorX, cursorY))
    rule updateWrappedCursor(Fact):
      what:
        (id, WrappedCursorX, cursorX)
        (id, WrappedCursorY, cursorY)
      then:
        session.insert(id, WrappedCursor, (cursorX, cursorY))
    rule cursorChanged(Fact):
      what:
        (id, Cursor, cursor)
        (id, Lines, lines, then = false)
        (id, WrappedCursorX, wrappedCursorX, then = false)
        (id, WrappedCursorY, wrappedCursorY, then = false)
        (id, ToWrapped, toWrapped, then = false)
      then:
        let (newCursorX, newCursorY) = session.cursorChanged(id, cursor.x, cursor.y, lines)
        if newCursorX != cursor.x:
          session.insert(id, CursorX, newCursorX)
        if newCursorY != cursor.y:
          session.insert(id, CursorY, newCursorY)
        if toWrapped.hasKey(newCursorY):
          for (wrappedLineNum, startCol, endCol) in toWrapped[newCursorY]:
            if newCursorX >= startCol and newCursorX <= endCol:
              let
                newWrappedCursorX = newCursorX - startCol
                newWrappedCursorY = wrappedLineNum
              if newWrappedCursorX != wrappedCursorX:
                session.insert(id, WrappedCursorX, newWrappedCursorX)
              if newWrappedCursorY != wrappedCursorY:
                session.insert(id, WrappedCursorY, newWrappedCursorY)
    rule wrappedCursorChanged(Fact):
      what:
        (id, WrappedCursor, wrappedCursor)
        (id, WrappedLines, lines, then = false)
        (id, CursorX, cursorX, then = false)
        (id, CursorY, cursorY, then = false)
        (id, ToUnwrapped, toUnwrapped, then = false)
      then:
        let (newWrappedCursorX, newWrappedCursorY) = session.cursorChanged(id, wrappedCursor.x, wrappedCursor.y, lines)
        if newWrappedCursorX != wrappedCursor.x:
          session.insert(id, WrappedCursorX, newWrappedCursorX)
        if newWrappedCursorY != wrappedCursor.y:
          session.insert(id, WrappedCursorY, newWrappedCursorY)
        if toUnwrapped.hasKey(newWrappedCursorY):
          let
            (lineNum, startCol, endCol) = toUnwrapped[newWrappedCursorY]
            newCursorX = newWrappedCursorX + startCol
            newCursorY = lineNum
          if newCursorX != cursorX:
            session.insert(id, CursorX, newCursorX)
          if newCursorY != cursorY:
            session.insert(id, CursorY, newCursorY)
    rule adjustWrappedCursorX(Fact):
      what:
        (id, WrappedLines, wrappedLines, then = false)
        (id, WrappedCursorX, wrappedCursorX)
        (id, WrappedCursorY, wrappedCursorY)
      then:
        # for each double width character before the cursor x, add 1
        session.insert(id, AdjustedWrappedCursorX, wrappedCursorX)
        if wrappedCursorY >= 0 and wrappedLines[].len > wrappedCursorY:
          let chars = wrappedLines[wrappedCursorY][].toRunes.stripCodes
          if wrappedCursorX >= 0 and chars.len >= wrappedCursorX:
            var adjust = 0
            for ch in chars[0 ..< wrappedCursorX]:
              if runewidth.runeWidth(ch) == 2:
                adjust += 1
            session.insert(id, AdjustedWrappedCursorX, wrappedCursorX + adjust)
    rule getBuffer(Fact):
      what:
        (id, CursorX, cursorX)
        (id, CursorY, cursorY)
        (id, WrappedCursorX, wrappedCursorX)
        (id, WrappedCursorY, wrappedCursorY)
        (id, AdjustedWrappedCursorX, adjustedWrappedCursorX)
        (id, ScrollX, scrollX)
        (id, ScrollY, scrollY)
        (id, Lines, lines)
        (id, WrappedLines, wrappedLines)
        (id, ToWrapped, toWrapped)
        (id, ToUnwrapped, toUnwrapped)
        (id, X, x)
        (id, Y, y)
        (id, Width, width)
        (id, Height, height)
        (id, Editable, editable)
        (id, SelectedMode, mode)
        (id, SelectedBrightness, brightness)
        (id, SelectedChar, selectedChar)
        (id, SelectedFgColor, selectedFgColor)
        (id, SelectedBgColor, selectedBgColor)
        (id, Prompt, prompt)
        (id, ValidCommands, commands)
        (id, InvalidCommands, errors)
        (id, Links, links)
        (id, UndoHistory, undoHistory)
        (id, UndoIndex, undoIndex)
        (id, InsertMode, insertMode)
        (id, LastEditTime, lastEditTime)
        (id, LastSaveTime, lastSaveTime)
      thenFinally:
        var t: BufferTable
        new t
        for buffer in session.queryAll(this):
          t[buffer.id] = buffer
        session.insert(Global, AllBuffers, t)

type
  EditorSession* = Session[Fact, FactMatch]

proc moveCursor(session: var auto, bufferId: int, x: int, y: int) =
  session.insert(bufferId, WrappedCursorX, x)
  session.insert(bufferId, WrappedCursorY, y)

proc onWindowResize(session: var EditorSession, width: int, height: int) =
  session.insert(TerminalWindow, Width, width)
  session.insert(TerminalWindow, Height, height)

proc getTerminalWindow(session: auto): tuple[width: int, height: int] =
  session.query(rules.getTerminalWindow)

proc insertBuffer(session: var EditorSession, id: Id, editable: bool, text: string) =
  session.insert(id, CursorX, 0)
  session.insert(id, CursorY, 0)
  session.insert(id, WrappedCursorX, 0)
  session.insert(id, WrappedCursorY, 0)
  session.insert(id, ScrollX, 0)
  session.insert(id, ScrollY, 0)
  session.insert(id, Lines, post.splitLines(text))
  session.insert(id, X, 0)
  session.insert(id, Y, 0)
  session.insert(id, Width, 0)
  session.insert(id, Height, 0)
  session.insert(id, Editable, editable)
  session.insert(id, SelectedMode, 0)
  session.insert(id, SelectedBrightness, 0)
  session.insert(id, SelectedChar, "█")
  session.insert(id, SelectedFgColor, "")
  session.insert(id, SelectedBgColor, "")
  session.insert(id, Prompt, None)
  var history: Snapshots
  new history
  session.insert(id, UndoHistory, history)
  session.insert(id, UndoIndex, -1)
  session.insert(id, InsertMode, false)
  session.insert(id, LastEditTime, 0.0)
  session.insert(id, LastSaveTime, 0.0)
  var cmdsRef, errsRef: RefCommands
  var linksRef: RefLinks
  new cmdsRef
  new errsRef
  new linksRef
  session.insert(id, ValidCommands, cmdsRef)
  session.insert(id, InvalidCommands, errsRef)
  session.insert(id, Links, linksRef)

proc saveBuffer*(f: File | StringStream, lines: RefStrings) =
  let lineCount = lines[].len
  var i = 0
  for line in lines[]:
    let s = line[]
    # write the line
    # if the only codes on the line are clears, remove them
    if codes.onlyHasClearParams(s):
      write(f, s.stripCodes)
    else:
      write(f, s)
    # write newline char after every line except the last line
    if i != lineCount - 1:
      write(f, "\n")
    i.inc

proc saveToStorage*(session: var EditorSession, sig: string) =
  let globals = session.query(rules.getGlobals)
  let buffer = globals.buffers[Editor.ord]
  if buffer.editable and
      buffer.lastEditTime > buffer.lastSaveTime and
      times.epochTime() - buffer.lastEditTime > saveDelay:
    try:
      let body = post.joinLines(buffer.lines)
      if buffer.lines[].len == 1 and body.stripCodes == "":
        storage.remove(sig)
      else:
        discard storage.set(sig, body)
      insert(session, Editor, editor.LastSaveTime, times.epochTime())
    except Exception as ex:
      discard

proc setContent*(session: var EditorSession, content: string) =
  session.insert(Editor, Lines, post.splitLines(content))
  session.fireRules

proc setEditable*(session: var EditorSession, editable: bool) =
  session.insert(Editor, Editable, editable)

proc getEditor*(session: EditorSession): Buffer =
  let globals = session.query(rules.getGlobals)
  return globals.buffers[Editor.ord]

proc getSelectedBuffer*(session: EditorSession): Buffer =
  let globals = session.query(rules.getGlobals)
  return globals.buffers[globals.selectedBuffer]

proc isEmpty*(session: EditorSession): bool =
  let buffer = getEditor(session)
  buffer.lines[].len == 1 and post.joinLines(buffer.lines).stripCodes == ""

proc scrollDown*(session: var EditorSession) =
  let
    globals = session.query(rules.getGlobals)
    buffer = globals.buffers[globals.selectedBuffer]
  session.insert(buffer.id, WrappedCursorY, buffer.wrappedCursorY + linesPerScroll)

proc scrollUp*(session: var EditorSession) =
  let
    globals = session.query(rules.getGlobals)
    buffer = globals.buffers[globals.selectedBuffer]
  session.insert(buffer.id, WrappedCursorY, buffer.wrappedCursorY - linesPerScroll)

proc isPlaying*(session: EditorSession): bool =
  let globals = session.query(rules.getGlobals)
  globals.midiProgress != nil

proc getSize*(buffer: tuple): tuple[x: int, y: int, width: int, height: int] =
  (buffer.x + 1, buffer.y + 1, buffer.width, buffer.height)

proc getSize*(session: EditorSession): tuple[x: int, y: int, width: int, height: int] =
  let buffer = getEditor(session)
  getSize(buffer)

proc isEditorTab*(session: EditorSession): bool =
  let globals = session.query(rules.getGlobals)
  globals.selectedBuffer == Editor.ord

var
  clipboard*: seq[string]
  copyCallback*: proc (lines: seq[string])

proc copyLines*(lines: seq[string]) =
  clipboard = lines
  if copyCallback != nil:
    copyCallback(lines)

proc copyLine(buffer: tuple) =
  if buffer.cursorY < buffer.lines[].len:
    copyLines(@[buffer.lines[buffer.cursorY][].stripCodes])

proc pasteLines(session: var EditorSession, buffer: tuple) =
  if clipboard.len > 0 and buffer.cursorY < buffer.lines[].len:
    var newLines: RefStrings
    new newLines
    newLines[] = buffer.lines[][0 ..< buffer.cursorY]
    for line in clipboard:
      post.add(newLines, line)
    newLines[] &= buffer.lines[][buffer.cursorY + 1 ..< buffer.lines[].len]
    session.insert(buffer.id, Lines, newLines)
    # force cursor to refresh in case it is out of bounds
    session.insert(buffer.id, CursorX, buffer.cursorX)

proc initLink*(ansiwave: string): string =
  let
    output = zippy.compress(ansiwave, dataFormat = zippy.dfZlib)
    pairs = {
      "data": paths.encode(output)
    }
  var fragments: seq[string]
  for pair in pairs:
    if pair[1].len > 0:
      fragments.add(pair[0] & ":" & pair[1])
  paths.initUrl(paths.address, "view.html#" & strutils.join(fragments, ","))

proc parseHash*(hash: string): Table[string, string] =
  let pairs = strutils.split(hash, ",")
  for pair in pairs:
    let keyVal = strutils.split(pair, ":")
    if keyVal.len == 2:
      result[keyVal[0]] =
        if keyVal[0] == "data":
          zippy.uncompress(paths.decode(keyVal[1]), dataFormat = zippy.dfZlib)
        else:
          keyVal[1]

proc copyLink*(link: string) =
  # echo the link to the terminal so the user can copy it
  iw.deinit()
  terminal.showCursor()
  for i in 0 ..< 100:
    echo ""
  echo link
  echo ""
  echo "Copy the link above, and then press Enter to return to ANSIWAVE."
  var s: TaintedString
  discard readLine(stdin, s)
  iw.init(fullscreen=true, mouse=true)
  terminal.hideCursor()

proc setCursor*(tb: var iw.TerminalBuffer, col: int, row: int) =
  if col < 0 or row < 0:
    return
  var ch = tb[col, row]
  ch.bg = iw.BackgroundColor(kind: iw.SimpleColor, simpleColor: terminal.bgYellow)
  if ch.fg == iw.ForegroundColor(kind: iw.SimpleColor, simpleColor: terminal.fgYellow):
    ch.fg = iw.ForegroundColor(kind: iw.SimpleColor, simpleColor: terminal.fgWhite)
  elif $ch.ch == "█":
    ch.fg = iw.ForegroundColor(kind: iw.SimpleColor, simpleColor: terminal.fgYellow)
  ch.cursor = true
  tb[col, row] = ch
  iw.setCursorPos(tb, col, row)

proc onInput*(session: var EditorSession, key: iw.Key, buffer: tuple): bool =
  let editable = buffer.editable and buffer.mode == 0
  case key:
  of iw.Key.Backspace:
    if not editable:
      return false
    if buffer.cursorX == 0:
      session.insert(buffer.id, Prompt, DeleteLine)
    elif buffer.cursorX > 0:
      let
        line = buffer.lines[buffer.cursorY][].toRunes
        realX = codes.getRealX(line, buffer.cursorX - 1)
        before = line[0 ..< realX]
      var after = line[realX + 1 ..< line.len]
      if buffer.insertMode:
        after = @[" ".runeAt(0)] & after
      let newLine = codes.dedupeCodes($before & $after)
      var newLines = buffer.lines
      post.set(newLines, buffer.cursorY, newLine)
      session.insert(buffer.id, Lines, newLines)
      session.insert(buffer.id, CursorX, buffer.cursorX - 1)
  of iw.Key.Delete:
    if not editable:
      return false
    let charCount = buffer.lines[buffer.cursorY][].stripCodes.runeLen
    if buffer.cursorX == charCount and buffer.cursorY < buffer.lines[].len - 1:
      var newLines = buffer.lines
      post.set(newLines, buffer.cursorY, codes.dedupeCodes(newLines[buffer.cursorY][] & newLines[buffer.cursorY + 1][]))
      newLines[].delete(buffer.cursorY + 1)
      session.insert(buffer.id, Lines, newLines)
    elif buffer.cursorX < charCount:
      let
        line = buffer.lines[buffer.cursorY][].toRunes
        realX = codes.getRealX(line, buffer.cursorX)
        newLine = codes.dedupeCodes($line[0 ..< realX] & $line[realX + 1 ..< line.len])
      var newLines = buffer.lines
      post.set(newLines, buffer.cursorY, newLine)
      session.insert(buffer.id, Lines, newLines)
  of iw.Key.Enter:
    if not editable:
      return false
    let
      line = buffer.lines[buffer.cursorY][].toRunes
      realX = codes.getRealX(line, buffer.cursorX)
      prefix = "\e[" & strutils.join(@[0] & codes.getParamsBeforeRealX(line, realX), ";") & "m"
      before = line[0 ..< realX]
      after = line[realX ..< line.len]
    var newLines: RefStrings
    new newLines
    newLines[] = buffer.lines[][0 ..< buffer.cursorY]
    post.add(newLines, codes.dedupeCodes($before))
    post.add(newLines, codes.dedupeCodes(prefix & $after))
    newLines[] &= buffer.lines[][buffer.cursorY + 1 ..< buffer.lines[].len]
    session.insert(buffer.id, Lines, newLines)
    session.insert(buffer.id, CursorX, 0)
    session.insert(buffer.id, CursorY, buffer.cursorY + 1)
  of iw.Key.Up:
    session.insert(buffer.id, WrappedCursorY, buffer.wrappedCursorY - 1)
  of iw.Key.Down:
    session.insert(buffer.id, WrappedCursorY, buffer.wrappedCursorY + 1)
  of iw.Key.Left:
    session.insert(buffer.id, CursorX, buffer.cursorX - 1)
  of iw.Key.Right:
    session.insert(buffer.id, CursorX, buffer.cursorX + 1)
  of iw.Key.Home:
    session.insert(buffer.id, CursorX, 0)
  of iw.Key.End:
    session.insert(buffer.id, CursorX, buffer.lines[buffer.cursorY][].stripCodes.runeLen)
  of iw.Key.PageUp, iw.Key.CtrlU:
    session.insert(buffer.id, WrappedCursorY, buffer.wrappedCursorY - int(buffer.height / 2))
  of iw.Key.PageDown, iw.Key.CtrlD:
    session.insert(buffer.id, WrappedCursorY, buffer.wrappedCursorY + int(buffer.height / 2))
  of iw.Key.Tab:
    case buffer.prompt:
    of DeleteLine:
      var newLines = buffer.lines
      if newLines[].len == 1:
        post.set(newLines, 0, "")
      else:
        newLines[].delete(buffer.cursorY)
      session.insert(buffer.id, Lines, newLines)
      if buffer.cursorY > newLines[].len - 1:
        session.insert(buffer.id, CursorY, newLines[].len - 1)
    else:
      discard
  of iw.Key.Insert:
    if not editable:
      return false
    session.insert(buffer.id, InsertMode, not buffer.insertMode)
  of iw.Key.CtrlK, iw.Key.CtrlC:
    copyLine(buffer)
  of iw.Key.CtrlL, iw.Key.CtrlV:
    if editable:
      pasteLines(session, buffer)
  else:
    return false
  true

proc makePrefix(buffer: tuple): string =
  if buffer.selectedFgColor == "" and buffer.selectedBgColor != "":
    result = "\e[0m" & buffer.selectedBgColor
  elif buffer.selectedFgColor != "" and buffer.selectedBgColor == "":
    result = "\e[0m" & buffer.selectedFgColor
  elif buffer.selectedFgColor == "" and buffer.selectedBgColor == "":
    result = "\e[0m"
  elif buffer.selectedFgColor != "" and buffer.selectedBgColor != "":
    result = buffer.selectedFgColor & buffer.selectedBgColor

proc onInput*(session: var EditorSession, code: uint32, buffer: tuple): bool =
  if buffer.mode != 0 or code < 32:
    return false
  let ch = cast[Rune](code)
  if not buffer.editable:
    return false
  let
    line = buffer.lines[buffer.cursorY][].toRunes
    realX = codes.getRealX(line, buffer.cursorX)
    before = line[0 ..< realX]
    after = line[realX ..< line.len]
    paramsBefore = codes.getParamsBeforeRealX(line, realX)
    prefix = buffer.makePrefix
    suffix = "\e[" & strutils.join(@[0] & paramsBefore, ";") & "m"
    chColored =
      # if the only param before is a clear, and the current param is a clear, no need for prefix/suffix at all
      if paramsBefore == @[0] and prefix == "\e[0m":
        $ch
      else:
        prefix & $ch & suffix
    newLine =
      if buffer.insertMode and after.len > 0: # replace the existing text rather than push it to the right
        codes.dedupeCodes($before & chColored & $after[1 ..< after.len])
      else:
        codes.dedupeCodes($before & chColored & $after)
  var newLines = buffer.lines
  post.set(newLines, buffer.cursorY, newLine)
  session.insert(buffer.id, Lines, newLines)
  session.insert(buffer.id, CursorX, buffer.cursorX + 1)
  true

proc renderBuffer(session: var EditorSession, tb: var iw.TerminalBuffer, buffer: tuple, input: tuple[key: iw.Key, codepoint: uint32], focused: bool) =
  session.insert(buffer.id, X, iw.x(tb))
  session.insert(buffer.id, Y, iw.y(tb))
  session.insert(buffer.id, Width, iw.width(tb)-2)
  session.insert(buffer.id, Height, iw.height(tb)-2)

  iw.drawRect(tb, 0, 0, iw.width(tb)-1, iw.height(tb)-1, doubleStyle = focused)

  let
    lines = buffer.wrappedLines[]
    scrollX = buffer.scrollX
    scrollY = buffer.scrollY
  var screenLine = 0
  for i in scrollY ..< lines.len:
    if screenLine > buffer.height - 1:
      break
    var line = lines[i][].toRunes
    if scrollX < line.stripCodes.len:
      if scrollX > 0:
        codes.deleteBefore(line, scrollX)
    else:
      line = @[]
    codes.deleteAfter(line, buffer.width - 1)
    tui.writeMaybe(tb, 1, 1 + screenLine, $line)
    if buffer.prompt != StopPlaying and buffer.mode == 0:
      # press gutter button with mouse or Tab
      if buffer.links[].contains(i):
        let linkY = 1 + screenLine
        iw.write(tb, 0, linkY, $buffer.links[i].icon)
        if input.key == iw.Key.Mouse:
          let info = iw.getMouse()
          if info.button == iw.MouseButton.mbLeft and info.action == iw.MouseButtonAction.mbaPressed:
            if info.x == 0 and info.y == linkY:
              session.insert(buffer.id, WrappedCursorX, 0)
              session.insert(buffer.id, WrappedCursorY, i)
              let hintText =
                if buffer.links[i].error:
                  if buffer.id == Editor.ord:
                    "hint: see the error with tab"
                  elif buffer.id == Errors.ord:
                    "hint: see where the error happened with tab"
                  else:
                    ""
                else:
                  "hint: play the current line with tab"
              session.insert(Global, HintText, hintText)
              session.insert(Global, HintTime, times.epochTime() + hintSecs)
              buffer.links[i].callback()
        elif i == buffer.wrappedCursorY and input.key == iw.Key.Tab and buffer.prompt == None:
          buffer.links[i].callback()
    screenLine += 1

  if input.key == iw.Key.Mouse:
    let info = iw.getMouse()
    if info.button == iw.MouseButton.mbLeft and info.action == iw.MouseButtonAction.mbaPressed:
      session.insert(buffer.id, Prompt, None)
      if info.x >= 0 and
          info.x <= 0 + buffer.width and
          info.y >= 0 and
          info.y <= buffer.height:
        # adjust x for double width characters
        var adjust = 0
        for col in 0 ..< info.x:
          if runewidth.runeWidth(tb[col, info.y].ch) == 2:
            adjust -= 1
        if buffer.mode == 0:
          session.insert(buffer.id, WrappedCursorX, info.x - (1 - buffer.scrollX) + adjust)
          session.insert(buffer.id, WrappedCursorY, info.y - (1 - buffer.scrollY))
        elif buffer.mode == 1:
          let
            x = info.x - 1 + buffer.scrollX + adjust
            y = info.y - 1 + buffer.scrollY
          if x >= 0 and y >= 0:
            var lines = buffer.wrappedLines
            while y > lines[].len - 1:
              post.add(lines, "")
            var line = lines[y][].toRunes
            while x > line.stripCodes.len - 1:
              line.add(" ".runeAt(0))
            let
              realX = codes.getRealX(line, x)
              prefix = buffer.makePrefix
              suffix = "\e[" & strutils.join(@[0] & codes.getParamsBeforeRealX(line, realX), ";") & "m"
              oldChar = line[realX].toUTF8
              newChar = if oldChar in wavescript.whitespaceChars: buffer.selectedChar else: oldChar
            post.set(lines, y, codes.dedupeCodes($line[0 ..< realX] & prefix & newChar & suffix & $line[realX + 1 ..< line.len]))
            session.insert(buffer.id, Lines, unwrapLines(lines, buffer.toUnwrapped))
    elif info.scroll:
      case info.scrollDir:
      of iw.ScrollDirection.sdNone:
        discard
      of iw.ScrollDirection.sdUp:
        session.insert(buffer.id, WrappedCursorY, buffer.wrappedCursorY - linesPerScroll)
      of iw.ScrollDirection.sdDown:
        session.insert(buffer.id, WrappedCursorY, buffer.wrappedCursorY + linesPerScroll)
  elif focused:
    if input.codepoint != 0:
      session.insert(buffer.id, Prompt, None)
      discard onInput(session, input.codepoint, buffer)
    elif input.key != iw.Key.None:
      session.insert(buffer.id, Prompt, None)
      discard onInput(session, input.key, buffer) or onInput(session, input.key.ord.uint32, buffer)

  if not (defined(emscripten) and buffer.id == Editor.ord and buffer.mode == 0):
    let
      col = 1 + buffer.adjustedWrappedCursorX - buffer.scrollX
      row = 1 + buffer.wrappedCursorY - buffer.scrollY
    if buffer.mode == 0 or buffer.prompt == StopPlaying:
      setCursor(tb, col, row)
    var
      xBlock = tb[col, buffer.height + 1]
      yBlock = tb[buffer.width + 1, row]
    const
      dash = "-".toRunes[0]
      pipe = "|".toRunes[0]
    xBlock.ch = dash
    yBlock.ch = pipe
    tb[col, buffer.height + 1] = xBlock
    tb[buffer.width + 1, row] = yBlock

  var prompt = ""
  case buffer.prompt:
  of None:
    if buffer.mode == 0 and buffer.insertMode:
      prompt = "press insert to turn off insert mode"
  of DeleteLine:
    if buffer.mode == 0:
      prompt = "press tab to delete the current line"
  of StopPlaying:
    prompt = "press esc to stop playing"
  if prompt.len > 0:
    let x = 1 + buffer.width - prompt.runeLen
    iw.write(tb, max(x, 1), 0, prompt)

proc renderRadioButtons(session: var EditorSession, tb: var iw.TerminalBuffer, x: int, y: int, choices: openArray[tuple[id: int, label: string, callback: proc ()]], selected: int, key: iw.Key, horiz: bool, shortcut: tuple[key: set[iw.Key], hint: string]): int =
  const space = 2
  var
    xx = x
    yy = y
  for i in 0 ..< choices.len:
    let choice = choices[i]
    if choice.id == selected:
      iw.write(tb, xx, yy, "→")
    iw.write(tb, xx + space, yy, choice.label)
    let
      oldX = xx
      newX = xx + space + choice.label.runeLen + 1
      oldY = yy
      newY = if horiz: yy else: yy + 1
    if key == iw.Key.Mouse:
      let info = iw.getMouse()
      if info.button == iw.MouseButton.mbLeft and info.action == iw.MouseButtonAction.mbaPressed:
        if info.x >= oldX and
            info.x <= newX and
            info.y == oldY:
          session.insert(Global, HintText, shortcut.hint)
          session.insert(Global, HintTime, times.epochTime() + hintSecs)
          choice.callback()
    elif choice.id == selected and key in shortcut.key:
      let nextChoice =
        if i+1 == choices.len:
          choices[0]
        else:
          choices[i+1]
      nextChoice.callback()
    if horiz:
      xx = newX
    else:
      yy = newY
  if not horiz:
    let labelWidths = sequtils.map(choices, proc (x: tuple): int = x.label.runeLen)
    xx += labelWidths[sequtils.maxIndex(labelWidths)] + space + 1
  return xx

proc renderButton(session: var EditorSession, tb: var iw.TerminalBuffer, text: string, x: int, y: int, key: iw.Key, cb: proc (), shortcut: tuple[key: set[iw.Key], hint: string] = ({}, "")): int =
  tui.write(tb, x, y, text)
  result = x + text.stripCodes.runeLen + 2
  if key == iw.Key.Mouse:
    let info = iw.getMouse()
    if info.button == iw.MouseButton.mbLeft and info.action == iw.MouseButtonAction.mbaPressed:
      if info.x >= x and
          info.x < result and
          info.y == y:
        if shortcut.hint.len > 0:
          session.insert(Global, HintText, shortcut.hint)
          session.insert(Global, HintTime, times.epochTime() + hintSecs)
        cb()
  elif key in shortcut.key:
    cb()

proc renderColors(session: var EditorSession, tb: var iw.TerminalBuffer, buffer: tuple, input: tuple[key: iw.Key, codepoint: uint32], colorX: int, colorY: int): int =
  const
    colorFgDarkCodes    = ["", "\e[22;30m", "\e[22;31m", "\e[22;32m", "\e[22;33m", "\e[22;34m", "\e[22;35m", "\e[22;36m", "\e[22;37m"]
    colorFgBrightCodes  = ["", "\e[1;30m", "\e[1;31m", "\e[1;32m", "\e[1;33m", "\e[1;34m", "\e[1;35m", "\e[1;36m", "\e[1;37m"]
    colorBgDarkCodes    = ["", "\e[22;40m", "\e[22;41m", "\e[22;42m", "\e[22;43m", "\e[22;44m", "\e[22;45m", "\e[22;46m", "\e[22;47m"]
    colorBgBrightCodes  = ["", "\e[1;40m", "\e[1;41m", "\e[1;42m", "\e[1;43m", "\e[1;44m", "\e[1;45m", "\e[1;46m", "\e[1;47m"]
    colorFgShortcuts    = ['x', 'k', 'r', 'g', 'y', 'b', 'm', 'c', 'w']
    colorFgShortcutsSet = {'x', 'k', 'r', 'g', 'y', 'b', 'm', 'c', 'w'}
    colorBgShortcuts    = ['X', 'K', 'R', 'G', 'Y', 'B', 'M', 'C', 'W']
    colorBgShortcutsSet = {'X', 'K', 'R', 'G', 'Y', 'B', 'M', 'C', 'W'}
    colorNames          = ["default", "black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"]
  let
    colorFgCodes =
      if buffer.brightness == 0:
        colorFgDarkCodes
      else:
        colorFgBrightCodes
    colorBgCodes =
      if buffer.brightness == 0:
        colorBgDarkCodes
      else:
        colorBgBrightCodes
  result = colorX + colorFgCodes.len * 3 + 1
  var colorChars = ""
  for code in colorFgCodes:
    if code == "":
      colorChars &= "⎕⎕"
    else:
      colorChars &= code & "██\e[0m"
    colorChars &= " "
  let fgIndex = find(colorFgCodes, buffer.selectedFgColor)
  let bgIndex = find(colorBgCodes, buffer.selectedBgColor)
  tui.write(tb, colorX, colorY, colorChars)
  iw.write(tb, colorX + fgIndex * 3, colorY + 1, "↑")
  tui.write(tb, colorX + bgIndex * 3 + 1, colorY + 1, "↑")
  if input.key == iw.Key.Mouse:
    let info = iw.getMouse()
    if info.y == colorY:
      if info.action == iw.MouseButtonAction.mbaPressed:
        if info.button == iw.MouseButton.mbLeft:
          let index = int((info.x - colorX) / 3)
          if index >= 0 and index < colorFgCodes.len:
            session.insert(buffer.id, SelectedFgColor, colorFgCodes[index])
            if buffer.mode == 1:
              session.insert(Global, HintText, "hint: press " & colorFgShortcuts[index] & " for " & colorNames[index] & " foreground")
              session.insert(Global, HintTime, times.epochTime() + hintSecs)
        elif info.button == iw.MouseButton.mbRight:
          let index = int((info.x - colorX) / 3)
          if index >= 0 and index < colorBgCodes.len:
            session.insert(buffer.id, SelectedBgColor, colorBgCodes[index])
            if buffer.mode == 1:
              session.insert(Global, HintText, "hint: press " & colorBgShortcuts[index] & " for " & colorNames[index] & " background")
              session.insert(Global, HintTime, times.epochTime() + hintSecs)
  elif buffer.mode == 1:
    try:
      let ch =
        if input.codepoint != 0:
          char(input.codepoint)
        else:
          char(input.key.ord)
      if ch in colorFgShortcutsSet:
        let index = find(colorFgShortcuts, ch)
        session.insert(buffer.id, SelectedFgColor, colorFgCodes[index])
      elif ch in colorBgShortcutsSet:
        let index = find(colorBgShortcuts, ch)
        session.insert(buffer.id, SelectedBgColor, colorBgCodes[index])
    except:
      discard
  var sess = session
  let
    darkCallback = proc () =
      sess.insert(buffer.id, SelectedBrightness, 0)
      sess.insert(buffer.id, SelectedFgColor, colorFgDarkCodes[fgIndex])
      sess.insert(buffer.id, SelectedBgColor, colorBgDarkCodes[bgIndex])
    brightCallback = proc () =
      sess.insert(buffer.id, SelectedBrightness, 1)
      sess.insert(buffer.id, SelectedFgColor, colorFgBrightCodes[fgIndex])
      sess.insert(buffer.id, SelectedBgColor, colorBgBrightCodes[bgIndex])
    choices = [
      (id: 0, label: "•", callback: darkCallback),
      (id: 1, label: "☼", callback: brightCallback),
    ]
    shortcut = (key: {iw.Key.CtrlB}, hint: "hint: change brightness with ctrl b")
  result = renderRadioButtons(session, tb, result, colorY, choices, buffer.brightness, input.key, false, shortcut)

proc renderBrushes(session: var EditorSession, tb: var iw.TerminalBuffer, buffer: tuple, key: iw.Key, brushX: int, brushY: int): int =
  const
    brushChars        = ["█", "▓", "▒", "░", "▀", "▄", "▌", "▐"]
    brushShortcuts    = ['1', '2', '3', '4', '5', '6', '7', '8']
    brushShortcutsSet = {'1', '2', '3', '4', '5', '6', '7', '8'}
  # make sure that all brush chars are treated as whitespace by wavescript
  static: assert brushChars.toHashSet < wavescript.whitespaceChars
  var brushCharsColored = ""
  for ch in brushChars:
    brushCharsColored &= buffer.selectedFgColor & buffer.selectedBgColor
    brushCharsColored &= ch
    brushCharsColored &= "\e[0m "
  result = brushX + brushChars.len * 2 + 1
  let brushIndex = find(brushChars, buffer.selectedChar)
  tui.write(tb, brushX, brushY, brushCharsColored)
  iw.write(tb, brushX + brushIndex * 2, brushY + 1, "↑")
  if key == iw.Key.Mouse:
    let info = iw.getMouse()
    if info.button == iw.MouseButton.mbLeft and info.action == iw.MouseButtonAction.mbaPressed:
      if info.y == brushY:
        let index = int((info.x - brushX) / 2)
        if index >= 0 and index < brushChars.len:
          session.insert(buffer.id, SelectedChar, brushChars[index])
          if buffer.mode == 1:
            session.insert(Global, HintText, "hint: press " & brushShortcuts[index] & " for that brush")
            session.insert(Global, HintTime, times.epochTime() + hintSecs)
  elif buffer.mode == 1:
    try:
      let ch = char(key.ord)
      if ch in brushShortcutsSet:
        let index = find(brushShortcuts, ch)
        session.insert(buffer.id, SelectedChar, brushChars[index])
    except:
      discard

proc undo(session: var EditorSession, buffer: tuple) =
  if buffer.undoIndex > 0:
    session.insert(buffer.id, UndoIndex, buffer.undoIndex - 1)

proc redo(session: var EditorSession, buffer: tuple) =
  if buffer.undoIndex + 1 < buffer.undoHistory[].len:
    session.insert(buffer.id, UndoIndex, buffer.undoIndex + 1)

when defined(emscripten):
  from ../emscripten import nil

  proc browseImage(buffer: tuple) =
    emscripten.browseFile("insertFile")

proc init*(opts: Options, width: int, height: int, hash: Table[string, string] = initTable[string, string]()): EditorSession =
  var
    editorText: string
    isDataUri = false

  if hash.hasKey("data"):
    editorText = hash["data"]
    isDataUri = true
  elif opts.input != "" and os.fileExists(opts.input):
    editorText = readFile(opts.input)
  else:
    editorText = ""

  result = initSession(autoFire = false)
  for r in rules.fields:
    result.add(r)

  const
    tutorialText = staticRead("../assets/tutorial.ansiwave")
    publishText = staticRead("../assets/publish.ansiwave")
  insertBuffer(result, Editor, not isDataUri, editorText)
  insertBuffer(result, Errors, false, "")
  insertBuffer(result, Tutorial, false, tutorialText)
  if not opts.bbsMode:
    insertBuffer(result, Publish, false, publishText)
  result.insert(Global, SelectedBuffer, Editor)
  result.insert(Global, HintText, "")
  result.insert(Global, HintTime, 0.0)
  result.insert(Global, MidiProgress, cast[MidiProgressType](nil))

  onWindowResize(result, width, height)

  result.insert(Global, Opts, opts)
  result.fireRules

  if opts.bbsMode and opts.sig != "":
    result.insert(Editor, Lines, post.splitLines(storage.get(opts.sig)))
    result.fireRules

proc tick*(session: var EditorSession, ctx: var nimwave.Context, rawInput: tuple[key: iw.Key, codepoint: uint32], focused: bool) =
  let
    width = iw.width(ctx.tb)
    height = iw.height(ctx.tb)
    termWindow = session.query(rules.getTerminalWindow)
    globals = session.query(rules.getGlobals)
    selectedBuffer = globals.buffers[globals.selectedBuffer]
    currentTime = times.epochTime()
    input: tuple[key: iw.Key, codepoint: uint32] =
      if globals.midiProgress != nil:
        (iw.Key.None, 0'u32) # ignore input while playing
      else:
        rawInput

  if termWindow != (width, height):
    onWindowResize(session, width, height)

  var sess = session

  # render top bar
  proc topBarView(ctx: var nimwave.Context, id: string, opts: JsonNode, children: seq[JsonNode]) =
    let id = Id(globals.selectedBuffer)
    ctx = nimwave.slice(ctx, 0, 0, iw.width(ctx.tb), if id == Editor: 2 else: 1)
    case id:
    of Editor:
      let playX =
        if selectedBuffer.prompt != StopPlaying and selectedBuffer.commands[].len > 0:
          renderButton(sess, ctx.tb, "♫ play", 1, 1, input.key, proc () = compileAndPlayAll(sess, selectedBuffer), (key: {iw.Key.CtrlP}, hint: "hint: play all lines with ctrl p"))
        else:
          0

      if selectedBuffer.editable:
        let titleX =
          when defined(emscripten):
            renderButton(sess, ctx.tb, "+ file", 1, 0, input.key, proc () = browseImage(selectedBuffer), (key: {iw.Key.CtrlO}, hint: "hint: open file with ctrl o"))
          else:
            renderButton(sess, ctx.tb, "\e[3m≈ANSIWAVE≈\e[0m", 1, 0, input.key, proc () = discard)
        var x = max(titleX, playX)

        let
          choices = [
            (id: 0, label: "write mode", callback: proc () = sess.insert(selectedBuffer.id, SelectedMode, 0)),
            (id: 1, label: "draw mode", callback: proc () = sess.insert(selectedBuffer.id, SelectedMode, 1)),
          ]
          shortcut = (key: {iw.Key.CtrlE}, hint: "hint: switch modes with ctrl e")
        x = renderRadioButtons(sess, ctx.tb, x, 0, choices, selectedBuffer.mode, input.key, false, shortcut)

        if selectedBuffer.mode == 1 or not defined(emscripten):
          x = renderColors(sess, ctx.tb, selectedBuffer, input, x + 1, 0)

        if selectedBuffer.mode == 0:
          when not defined(emscripten):
            discard renderButton(sess, ctx.tb, "↨ copy line", x, 0, input.key, proc () = copyLine(selectedBuffer), (key: {}, hint: "hint: copy line with ctrl " & (if iw.gIllwaveInitialized: "k" else: "c")))
            x = renderButton(sess, ctx.tb, "↨ paste", x, 1, input.key, proc () = pasteLines(sess, selectedBuffer), (key: {}, hint: "hint: paste with ctrl " & (if iw.gIllwaveInitialized: "l" else: "v")))
            x -= 1
            x = renderButton(sess, ctx.tb, "↔ insert", x, 1, input.key, proc () = discard onInput(sess, iw.Key.Insert, selectedBuffer), (key: {}, hint: "hint: insert with the insert key"))
        elif selectedBuffer.mode == 1:
          x = renderBrushes(sess, ctx.tb, selectedBuffer, input.key, x + 1, 0)

        if selectedBuffer.mode == 1 or not defined(emscripten):
          let undoX = renderButton(sess, ctx.tb, "◄ undo", x, 0, input.key, proc () = undo(sess, selectedBuffer), (key: {iw.Key.CtrlX, iw.Key.CtrlZ}, hint: "hint: undo with ctrl x"))
          let redoX = renderButton(sess, ctx.tb, "► redo", x, 1, input.key, proc () = redo(sess, selectedBuffer), (key: {iw.Key.CtrlR}, hint: "hint: redo with ctrl r"))
          x = max(undoX, redoX)
      elif not globals.options.bbsMode:
        let
          topText = "read-only mode! to edit this, convert it into an ansiwave:"
          bottomText = "ansiwave https://ansiwave.net/... hello.ansiwave"
        iw.write(ctx.tb, max(0, int(textWidth/2 - topText.runeLen/2)), 0, topText)
        iw.write(ctx.tb, max(playX, int(textWidth/2 - bottomText.runeLen/2)), 1, bottomText)
    of Errors:
      discard renderButton(sess, ctx.tb, "\e[3m≈ANSIWAVE≈ errors\e[0m", 1, 0, input.key, proc () = discard)
    of Tutorial:
      let titleX = renderButton(sess, ctx.tb, "\e[3m≈ANSIWAVE≈ tutorial\e[0m", 1, 0, input.key, proc () = discard)
      when not defined(emscripten):
        discard renderButton(sess, ctx.tb, "↨ copy line", titleX, 0, input.key, proc () = copyLine(selectedBuffer), (key: {}, hint: "hint: copy line with ctrl k"))
    of Publish:
      let
        titleX = renderButton(sess, ctx.tb, "\e[3m≈ANSIWAVE≈ publish\e[0m", 1, 0, input.key, proc () = discard)
        copyLinkCallback = proc () =
          let buffer = globals.buffers[Editor.ord]
          copyLink(initLink(post.joinLines(buffer.lines)))
          iw.setDoubleBuffering(false)
          var
            tb = iw.initTerminalBuffer(width, height)
            ctx = nimwave.initContext(tb)
          tick(sess, ctx, (iw.Key.None, 0'u32), focused)
          iw.display(ctx.tb)
          iw.setDoubleBuffering(true)
      discard renderButton(sess, ctx.tb, "↕ copy link", titleX, 0, input.key, copyLinkCallback, (key: {iw.Key.CtrlH}, hint: "hint: copy link with ctrl h"))
    else:
      discard
  ctx.components["top-bar"] = topBarView

  proc bufferView(ctx: var nimwave.Context, id: string, opts: JsonNode, children: seq[JsonNode]) =
    ctx = nimwave.slice(ctx, 0, 0, iw.width(ctx.tb), iw.height(ctx.tb)-1)
    renderBuffer(sess, ctx.tb, selectedBuffer, input, focused and selectedBuffer.prompt != StopPlaying)
  ctx.components["buffer"] = bufferView

  nimwave.render(ctx, %* ["vbox", ["top-bar"], ["buffer"]])

  # render bottom bar
  var x = 0
  if selectedBuffer.prompt != StopPlaying:
    var sess = session
    let
      editor = globals.buffers[Editor.ord]
      errorCount = editor.errors[].len
      choices = [
        (id: Editor.ord, label: "editor", callback: proc () {.closure.} = sess.insert(Global, SelectedBuffer, Editor)),
        (id: Errors.ord, label: strutils.format("errors ($1)", errorCount), callback: proc () {.closure.} = sess.insert(Global, SelectedBuffer, Errors)),
        (id: Tutorial.ord, label: "tutorial", callback: proc () {.closure.} = sess.insert(Global, SelectedBuffer, Tutorial)),
        (id: Publish.ord, label: "publish", callback: proc () {.closure.} = sess.insert(Global, SelectedBuffer, Publish)),
      ]
      shortcut = (key: {iw.Key.CtrlN}, hint: "hint: switch tabs with ctrl n")
    var selectedChoices = @choices
    selectedChoices.setLen(0)
    for choice in choices:
      if globals.buffers.hasKey(choice.id):
        selectedChoices.add(choice)
    x = renderRadioButtons(session, ctx.tb, 0, termWindow.height - 1, selectedChoices, globals.selectedBuffer, input.key, true, shortcut)

  # render hints
  if globals.hintTime > 0 and times.epochTime() >= globals.hintTime:
    session.insert(Global, HintText, "")
    session.insert(Global, HintTime, 0.0)
  else:
    let
      showHint = globals.hintText.len > 0
      text =
        if showHint:
          globals.hintText
        else:
          "‼ exit"
      textX = max(x + 2, selectedBuffer.width + 1 - text.runeLen)
    if showHint:
      tui.write(ctx.tb, textX, termWindow.height - 1, "\e[3m" & text & "\e[0m")
    elif selectedBuffer.prompt != StopPlaying and not globals.options.bbsMode:
      var sess = session
      let cb =
        proc () =
          sess.insert(Global, HintText, "press ctrl c to exit")
          sess.insert(Global, HintTime, times.epochTime() + hintSecs)
      discard renderButton(session, ctx.tb, text, textX, termWindow.height - 1, input.key, cb)

  if globals.midiProgress != nil:
    if not globals.midiProgress[].messageDisplayed:
      globals.midiProgress.messageDisplayed = true
      iw.fill(ctx.tb, 0, 0, textWidth + 1, (if selectedBuffer.id == Editor.ord: 1 else: 0), " ")
      iw.write(ctx.tb, 0, 0, "making music...")
    elif not globals.midiProgress[].started:
      if midi.soundfontReady():
        globals.midiProgress.started = true
        let currentTime = times.epochTime()
        let (secs, playResult) = midi.play(globals.midiProgress.events)
        if playResult.kind == sound.Error:
          session.insert(Global, MidiProgress, cast[MidiProgressType](nil))
        else:
          globals.midiProgress.time = (currentTime, currentTime + secs)
          globals.midiProgress.addrs = playResult.addrs
      else:
        iw.fill(ctx.tb, 0, 0, textWidth + 1, (if selectedBuffer.id == Editor.ord: 1 else: 0), " ")
        iw.write(ctx.tb, 0, 0, "fetching soundfont...")
    elif currentTime > globals.midiProgress.time.stop or rawInput.key in {iw.Key.Tab, iw.Key.Escape}:
      midi.stop(globals.midiProgress.addrs)
      session.insert(Global, MidiProgress, cast[MidiProgressType](nil))
      session.insert(selectedBuffer.id, Prompt, None)
    else:
      let
        secs = globals.midiProgress.time.stop - globals.midiProgress.time.start
        progress = currentTime - globals.midiProgress.time.start
      # go to the right line
      var lineTimesIdx = globals.midiProgress.lineTimes.len - 1
      while lineTimesIdx >= 0:
        let (line, time) = globals.midiProgress.lineTimes[lineTimesIdx]
        if progress >= time:
          moveCursor(session, selectedBuffer.id, 0, line)
          break
        else:
          lineTimesIdx -= 1
      # draw progress bar
      iw.fill(ctx.tb, 0, 0, textWidth + 1, (if selectedBuffer.id == Editor.ord: 1 else: 0), " ")
      iw.fill(ctx.tb, 0, 0, int((progress / secs) * float(textWidth + 1)), 0, "▓")
      session.insert(selectedBuffer.id, Prompt, StopPlaying)

