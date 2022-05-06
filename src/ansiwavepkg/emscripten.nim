import json

proc ansiwave_fetch(url: cstring, verb: cstring, headers: cstring, body: cstring): cstring {.importc.}
proc ansiwave_browse_file(callback: cstring) {.importc.}
proc ansiwave_start_download(data_uri: cstring, filename: cstring) {.importc.}
proc ansiwave_localstorage_set(key: cstring, val: cstring): bool {.importc.}
proc ansiwave_localstorage_get(key: cstring): cstring {.importc.}
proc ansiwave_localstorage_remove(key: cstring) {.importc.}
proc ansiwave_localstorage_list(): cstring {.importc.}
proc ansiwave_play_audio(src: cstring) {.importc.}
proc ansiwave_stop_audio() {.importc.}
proc free(p: pointer) {.importc.}

{.compile: "ansiwave_emscripten.c".}

proc browseFile*(callback: string) =
  ansiwave_browse_file(callback)

proc startDownload*(dataUri: string, filename: string) =
  ansiwave_start_download(dataUri, filename)

proc localSet*(key: string, val: string): bool =
  ansiwave_localstorage_set(key, val)

proc localGet*(key: string): string =
  let val = ansiwave_localstorage_get(key)
  result = $val
  free(val)

proc localRemove*(key: string) =
  ansiwave_localstorage_remove(key)

proc localList*(): seq[string] =
  let val = ansiwave_localstorage_list()
  for item in parseJson($val):
    result.add(item.str)
  free(val)

proc playAudio*(src: string) =
  ansiwave_play_audio(src)

proc stopAudio*() =
  ansiwave_stop_audio()

