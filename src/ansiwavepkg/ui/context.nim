from illwave as iw import nil
from nimwave import nil
import tables, json

var mouseInfo*: iw.MouseInfo

type
  ViewFocusArea* = tuple[tb: iw.TerminalBuffer, action: string, actionData: OrderedTable[string, JsonNode], copyableText: seq[string]]
  State* = object
    focusIndex*: int
    focusAreas*: ref seq[ViewFocusArea]
    input*: tuple[key: iw.Key, codepoint: uint32]
  Context* = nimwave.Context[State]
  RenderProc* = nimwave.RenderProc[State]

proc initContext*(): Context =
  nimwave.initContext[State]()
