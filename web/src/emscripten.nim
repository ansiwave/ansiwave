proc ansiweb_get_cursor_line(selector: cstring): cint {.importc.}

{.compile: "ansiweb_emscripten.c".}

proc getCursorLine*(selector: string): int =
  ansiweb_get_cursor_line(selector)
