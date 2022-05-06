when defined(emscripten):
  from ./emscripten import nil
  from wavecorepkg/paths import nil
else:
  from os import `/`

  const dataDir* = "~" / ".ansiwave"

proc set*(key: string, val: string | seq[uint8], isBinary: bool = false): bool =
  when defined(emscripten):
    let v =
      if isBinary:
        paths.encode(val)
      else:
        cast[string](val)
    emscripten.localSet(key, v)
  else:
    let dir = os.expandTilde(dataDir)
    os.createDir(dir)
    try:
      writeFile(dir / key, val)
      true
    except Exception as ex:
      false

proc get*(key: string, isBinary: bool = false): string =
  when defined(emscripten):
    let val = emscripten.localGet(key)
    if isBinary:
      paths.decode(val)
    else:
      val
  else:
    let path = os.expandTilde(dataDir / key)
    if os.fileExists(path):
      readFile(path)
    else:
      ""

proc remove*(key: string) =
  when defined(emscripten):
    emscripten.localRemove(key)
  else:
    let path = os.expandTilde(dataDir / key)
    if os.fileExists(path):
      os.removeFile(path)

proc list*(): seq[string] =
  when defined(emscripten):
    emscripten.localList()
  else:
    for f in os.walkDir(os.expandTilde(dataDir)):
      let (_, tail) = os.splitPath(f.path)
      result.add(tail)

