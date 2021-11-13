when defined(emscripten):
  from wavecorepkg/client/emscripten import nil
  from base64 import nil
else:
  from os import `/`

  const dataDir* = "~" / ".config" / "ansiwave"

proc set*(key: string, val: string | seq[uint8], isBinary: bool = false): bool =
  when defined(emscripten):
    let v =
      if isBinary:
        base64.encode(val, safe = true)
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
      base64.decode(val)
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

