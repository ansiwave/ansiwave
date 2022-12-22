from illwave as iw import nil
from nimwave as nw import nil
import tables, json

var mouseInfo*: iw.MouseInfo

type
  ViewFocusArea* = tuple[tb: iw.TerminalBuffer, action: string, actionData: Table[string, JsonNode], copyableText: seq[string]]
  State* = object
    focusIndex*: int
    focusAreas*: ref seq[ViewFocusArea]
    input*: tuple[key: iw.Key, codepoint: uint32]
  Context* = nw.Context[State]
  Rect* = ref object of nw.Node
    action*: string
    actionData*: Table[string, JsonNode]
    children*: seq[nw.Node]
    childrenAfter*: seq[nw.Node]
    topLeft*: string
    topRight*: string
    bottomLeft*: string
    bottomRight*: string
    bottomLeftFocused*: string
    copyableText*: seq[string]
    focused*: ref bool

proc initContext*(): Context =
  nw.initContext[State]()

include nimwave/prelude
