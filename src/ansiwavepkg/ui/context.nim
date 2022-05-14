from illwave as iw import nil
from nimwave import nil

type
  State* = object
  Context* = nimwave.Context[State]

proc initContext*(tb: iw.TerminalBuffer): Context =
  nimwave.initContext[State](tb)
