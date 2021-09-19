{.passC: "-Isrc/ansiwavepkg/chafa -Isrc/ansiwavepkg/chafa/internal".}
{.passC: "-mavx2".}
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

{.passC: "-Isrc/ansiwavepkg/chafa/glib -Isrc/ansiwavepkg/chafa/glib/gnulib".}
when defined(windows):
  {.passC: "-Isrc/ansiwavepkg/chafa/glib-windows".}
elif defined(macosx):
  {.passC: "-Isrc/ansiwavepkg/chafa/glib-macos".}
elif defined(linux):
  {.passC: "-Isrc/ansiwavepkg/chafa/glib-linux".}

{.passC: "-DGLIB_COMPILATION -DLIBDIR".}
{.compile: "src/ansiwavepkg/chafa/glib/gmessages.c".}
{.compile: "src/ansiwavepkg/chafa/glib/garcbox.c".}
{.compile: "src/ansiwavepkg/chafa/glib/garray.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gasyncqueue.c".}
#{.compile: "src/ansiwavepkg/chafa/glib/gatomic.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gbacktrace.c".}
#{.compile: "src/ansiwavepkg/chafa/glib/gbase64.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gbitlock.c".}
#{.compile: "src/ansiwavepkg/chafa/glib/gbookmarkfile.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gbytes.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gcharset.c".}
#{.compile: "src/ansiwavepkg/chafa/glib/gchecksum.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gconvert.c".}
#{.compile: "src/ansiwavepkg/chafa/glib/gdataset.c".}
#{.compile: "src/ansiwavepkg/chafa/glib/gdate.c".}
#{.compile: "src/ansiwavepkg/chafa/glib/gdatetime.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gdir.c".}
{.compile: "src/ansiwavepkg/chafa/glib/genviron.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gerror.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gfileutils.c".}
{.compile: "src/ansiwavepkg/chafa/glib/ggettext.c".}
{.compile: "src/ansiwavepkg/chafa/glib/ghash.c".}
#{.compile: "src/ansiwavepkg/chafa/glib/ghmac.c".}
#{.compile: "src/ansiwavepkg/chafa/glib/ghook.c".}
{.compile: "src/ansiwavepkg/chafa/glib/ghostutils.c".}
{.compile: "src/ansiwavepkg/chafa/glib/giochannel.c".}
when defined(windows):
  {.compile: "src/ansiwavepkg/chafa/glib/giowin32.c".}
else:
  {.compile: "src/ansiwavepkg/chafa/glib/giounix.c".}
#{.compile: "src/ansiwavepkg/chafa/glib/gkeyfile.c".}
{.compile: "src/ansiwavepkg/chafa/glib/glib-init.c".}
#{.compile: "src/ansiwavepkg/chafa/glib/glib-private.c".}
when not defined(windows):
  {.compile: "src/ansiwavepkg/chafa/glib/glib-unix.c".}
{.compile: "src/ansiwavepkg/chafa/glib/glist.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gmain.c".}
#{.compile: "src/ansiwavepkg/chafa/glib/gmappedfile.c".}
#{.compile: "src/ansiwavepkg/chafa/glib/gmarkup.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gmem.c".}
#{.compile: "src/ansiwavepkg/chafa/glib/gnode.c".}
{.compile: "src/ansiwavepkg/chafa/glib/goption.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gpattern.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gpoll.c".}
#{.compile: "src/ansiwavepkg/chafa/glib/gprimes.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gprintf.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gqsort.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gquark.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gqueue.c".}
{.compile: "src/ansiwavepkg/chafa/glib/grand.c".}
{.compile: "src/ansiwavepkg/chafa/glib/grcbox.c".}
{.compile: "src/ansiwavepkg/chafa/glib/grefcount.c".}
#{.compile: "src/ansiwavepkg/chafa/glib/grefstring.c".}
#{.compile: "src/ansiwavepkg/chafa/glib/gregex.c".}
#{.compile: "src/ansiwavepkg/chafa/glib/gscanner.c".}
#{.compile: "src/ansiwavepkg/chafa/glib/gsequence.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gshell.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gslice.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gslist.c".}
when defined(windows):
  {.compile: "src/ansiwavepkg/chafa/glib/gspawn-win32-helper.c".}
  {.compile: "src/ansiwavepkg/chafa/glib/gspawn-win32.c".}
else:
  {.compile: "src/ansiwavepkg/chafa/glib/gspawn.c".}
#{.compile: "src/ansiwavepkg/chafa/glib/gstdio-private.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gstdio.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gstrfuncs.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gstring.c".}
#{.compile: "src/ansiwavepkg/chafa/glib/gstringchunk.c".}
#{.compile: "src/ansiwavepkg/chafa/glib/gstrvbuilder.c".}
#{.compile: "src/ansiwavepkg/chafa/glib/gtester.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gtestutils.c".}
when defined(windows):
  {.compile: "src/ansiwavepkg/chafa/glib/gthread-win32.c".}
else:
  {.compile: "src/ansiwavepkg/chafa/glib/gthread-posix.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gthread.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gthreadpool.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gtimer.c".}
#{.compile: "src/ansiwavepkg/chafa/glib/gtimezone.c".}
#{.compile: "src/ansiwavepkg/chafa/glib/gtrace.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gtranslit.c".}
#{.compile: "src/ansiwavepkg/chafa/glib/gtrashstack.c".}
#{.compile: "src/ansiwavepkg/chafa/glib/gtree.c".}
#{.compile: "src/ansiwavepkg/chafa/glib/gunibreak.c".}
#{.compile: "src/ansiwavepkg/chafa/glib/gunicollate.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gunidecomp.c".}
{.compile: "src/ansiwavepkg/chafa/glib/guniprop.c".}
{.compile: "src/ansiwavepkg/chafa/glib/guri.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gutf8.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gutils.c".}
#{.compile: "src/ansiwavepkg/chafa/glib/guuid.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gvariant-core.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gvariant-parser.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gvariant-serialiser.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gvariant.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gvarianttype.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gvarianttypeinfo.c".}
#{.compile: "src/ansiwavepkg/chafa/glib/gversion.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gwakeup.c".}
when defined(windows):
  {.compile: "src/ansiwavepkg/chafa/glib/gwin32-private.c".}
  {.compile: "src/ansiwavepkg/chafa/glib/gwin32.c".}

{.compile: "src/ansiwavepkg/chafa/glib/libcharset/localcharset.c".}

{.compile: "src/ansiwavepkg/chafa/glib/gnulib/asnprintf.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gnulib/frexp.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gnulib/frexpl.c".}
#{.compile: "src/ansiwavepkg/chafa/glib/gnulib/isinf.c".}
#{.compile: "src/ansiwavepkg/chafa/glib/gnulib/isnan.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gnulib/isnand.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gnulib/isnanf.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gnulib/isnanl.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gnulib/printf-args.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gnulib/printf-frexp.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gnulib/printf-frexpl.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gnulib/printf-parse.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gnulib/printf.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gnulib/signbitd.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gnulib/signbitf.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gnulib/signbitl.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gnulib/vasnprintf.c".}
{.compile: "src/ansiwavepkg/chafa/glib/gnulib/xsize.c".}

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
