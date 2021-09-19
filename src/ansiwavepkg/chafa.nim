{.passC: "-I/usr/include/glib-2.0 -I/usr/lib/x86_64-linux-gnu/glib-2.0/include/ -Isrc/ansiwavepkg/chafa -Isrc/ansiwavepkg/chafa/internal".}
{.passC: "-mavx2".}
{.passL: "-lglib-2.0"}
{.compile: "chafa/chafa.c".}
{.compile: "chafa/chafa-canvas-config.c".}
{.compile: "chafa/chafa-canvas.c".}
{.compile: "chafa/chafa-features.c".}
{.compile: "chafa/chafa-symbol-map.c".}
{.compile: "chafa/chafa-term-db.c".}
{.compile: "chafa/chafa-term-info.c".}
{.compile: "chafa/chafa-util.c".}
{.compile: "chafa/internal/chafa-base64.c".}
{.compile: "chafa/internal/chafa-batch.c".}
{.compile: "chafa/internal/chafa-canvas-printer.c".}
{.compile: "chafa/internal/chafa-color-hash.c".}
{.compile: "chafa/internal/chafa-color-table.c".}
{.compile: "chafa/internal/chafa-color.c".}
{.compile: "chafa/internal/chafa-dither.c".}
{.compile: "chafa/internal/chafa-indexed-image.c".}
{.compile: "chafa/internal/chafa-iterm2-canvas.c".}
{.compile: "chafa/internal/chafa-kitty-canvas.c".}
{.compile: "chafa/internal/chafa-mmx.c".}
{.compile: "chafa/internal/chafa-palette.c".}
{.compile: "chafa/internal/chafa-pca.c".}
{.compile: "chafa/internal/chafa-pixops.c".}
{.compile: "chafa/internal/chafa-popcnt.c".}
{.compile: "chafa/internal/chafa-sixel-canvas.c".}
{.compile: "chafa/internal/chafa-sse41.c".}
{.compile: "chafa/internal/chafa-string-util.c".}
{.compile: "chafa/internal/chafa-symbols.c".}
{.compile: "chafa/internal/chafa-work-cell.c".}
{.compile: "chafa/internal/smolscale/smolscale-avx2.c".}
{.compile: "chafa/internal/smolscale/smolscale.c".}

type
  GString* {.bycopy.} = object
    str*: cstring
    len*: csize_t
    allocated_len*: csize_t

proc image_to_ansi(data: ptr uint8, width: cint, height: cint, out_width: cint): ptr GString {.importc.}
proc g_string_free(s: pointer, free_segment: cint) {.importc.}

import stb_image/read as stbi

proc imageToAnsi*(image: string, outWidth: cint): string =
  var width, height, channels: int
  var data = stbi.loadFromMemory(cast[seq[uint8]](image), width, height, channels, stbi.RGBA)
  var gs = image_to_ansi(data[0].addr, width.cint, height.cint, outWidth)
  result = $ gs.str
  chafa.g_string_free(gs, 1)
