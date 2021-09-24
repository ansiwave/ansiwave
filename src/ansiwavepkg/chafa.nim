when defined(amd64) and not defined(musl) and (defined(macosx) or defined(linux)):
  import os
  const dir = currentSourcePath().parentDir().joinPath("chafa")

  {.passC: "-I" & dir & " -I" & dir.joinPath("internal").}
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

  {.passC: "-I" & dir.joinPath("glib") & " -I" & dir.joinPath("glib/gnulib").}
  when defined(windows):
    {.passC: "-I" & dir.joinPath("glib-windows").}
    {.passL: "-luuid -lintl -lws2_32 -lole32"}
  elif defined(macosx):
    {.passC: "-I" & dir.joinPath("glib-macos").}
    {.passL: "-liconv -lintl -framework CoreFoundation -framework AppKit"}
  elif defined(linux):
    {.passC: "-I" & dir.joinPath("glib-linux").}

  {.passC: "-DGLIB_COMPILATION -DLIBDIR".}
  {.compile: "chafa/glib/gmessages.c".}
  {.compile: "chafa/glib/garcbox.c".}
  {.compile: "chafa/glib/garray.c".}
  {.compile: "chafa/glib/gasyncqueue.c".}
  #{.compile: "chafa/glib/gatomic.c".}
  {.compile: "chafa/glib/gbacktrace.c".}
  #{.compile: "chafa/glib/gbase64.c".}
  {.compile: "chafa/glib/gbitlock.c".}
  #{.compile: "chafa/glib/gbookmarkfile.c".}
  {.compile: "chafa/glib/gbytes.c".}
  {.compile: "chafa/glib/gcharset.c".}
  #{.compile: "chafa/glib/gchecksum.c".}
  {.compile: "chafa/glib/gconvert.c".}
  #{.compile: "chafa/glib/gdataset.c".}
  #{.compile: "chafa/glib/gdate.c".}
  #{.compile: "chafa/glib/gdatetime.c".}
  {.compile: "chafa/glib/gdir.c".}
  {.compile: "chafa/glib/genviron.c".}
  {.compile: "chafa/glib/gerror.c".}
  {.compile: "chafa/glib/gfileutils.c".}
  {.compile: "chafa/glib/ggettext.c".}
  {.compile: "chafa/glib/ghash.c".}
  #{.compile: "chafa/glib/ghmac.c".}
  #{.compile: "chafa/glib/ghook.c".}
  {.compile: "chafa/glib/ghostutils.c".}
  {.compile: "chafa/glib/giochannel.c".}
  when defined(windows):
    {.compile: "chafa/glib/giowin32.c".}
  else:
    {.compile: "chafa/glib/giounix.c".}
  #{.compile: "chafa/glib/gkeyfile.c".}
  {.compile: "chafa/glib/glib-init.c".}
  #{.compile: "chafa/glib/glib-private.c".}
  when not defined(windows):
    {.compile: "chafa/glib/glib-unix.c".}
  {.compile: "chafa/glib/glist.c".}
  {.compile: "chafa/glib/gmain.c".}
  #{.compile: "chafa/glib/gmappedfile.c".}
  #{.compile: "chafa/glib/gmarkup.c".}
  {.compile: "chafa/glib/gmem.c".}
  #{.compile: "chafa/glib/gnode.c".}
  {.compile: "chafa/glib/goption.c".}
  {.compile: "chafa/glib/gpattern.c".}
  {.compile: "chafa/glib/gpoll.c".}
  #{.compile: "chafa/glib/gprimes.c".}
  {.compile: "chafa/glib/gprintf.c".}
  {.compile: "chafa/glib/gqsort.c".}
  {.compile: "chafa/glib/gquark.c".}
  {.compile: "chafa/glib/gqueue.c".}
  {.compile: "chafa/glib/grand.c".}
  {.compile: "chafa/glib/grcbox.c".}
  {.compile: "chafa/glib/grefcount.c".}
  #{.compile: "chafa/glib/grefstring.c".}
  #{.compile: "chafa/glib/gregex.c".}
  #{.compile: "chafa/glib/gscanner.c".}
  #{.compile: "chafa/glib/gsequence.c".}
  {.compile: "chafa/glib/gshell.c".}
  {.compile: "chafa/glib/gslice.c".}
  {.compile: "chafa/glib/gslist.c".}
  when defined(windows):
    {.compile: "chafa/glib/gspawn-win32-helper.c".}
    {.compile: "chafa/glib/gspawn-win32.c".}
  else:
    {.compile: "chafa/glib/gspawn.c".}
  #{.compile: "chafa/glib/gstdio-private.c".}
  {.compile: "chafa/glib/gstdio.c".}
  {.compile: "chafa/glib/gstrfuncs.c".}
  {.compile: "chafa/glib/gstring.c".}
  #{.compile: "chafa/glib/gstringchunk.c".}
  #{.compile: "chafa/glib/gstrvbuilder.c".}
  #{.compile: "chafa/glib/gtester.c".}
  {.compile: "chafa/glib/gtestutils.c".}
  when defined(windows):
    {.compile: "chafa/glib/gthread-win32.c".}
  else:
    {.compile: "chafa/glib/gthread-posix.c".}
  {.compile: "chafa/glib/gthread.c".}
  {.compile: "chafa/glib/gthreadpool.c".}
  {.compile: "chafa/glib/gtimer.c".}
  #{.compile: "chafa/glib/gtimezone.c".}
  #{.compile: "chafa/glib/gtrace.c".}
  {.compile: "chafa/glib/gtranslit.c".}
  {.compile: "chafa/glib/gtrashstack.c".}
  #{.compile: "chafa/glib/gtree.c".}
  #{.compile: "chafa/glib/gunibreak.c".}
  #{.compile: "chafa/glib/gunicollate.c".}
  {.compile: "chafa/glib/gunidecomp.c".}
  {.compile: "chafa/glib/guniprop.c".}
  {.compile: "chafa/glib/guri.c".}
  {.compile: "chafa/glib/gutf8.c".}
  {.compile: "chafa/glib/gutils.c".}
  #{.compile: "chafa/glib/guuid.c".}
  {.compile: "chafa/glib/gvariant-core.c".}
  {.compile: "chafa/glib/gvariant-parser.c".}
  {.compile: "chafa/glib/gvariant-serialiser.c".}
  {.compile: "chafa/glib/gvariant.c".}
  {.compile: "chafa/glib/gvarianttype.c".}
  {.compile: "chafa/glib/gvarianttypeinfo.c".}
  #{.compile: "chafa/glib/gversion.c".}
  {.compile: "chafa/glib/gwakeup.c".}
  when defined(windows):
    #{.compile: "chafa/glib/gwin32-private.c".}
    {.compile: "chafa/glib/gwin32.c".}
  when defined(macosx):
    {.compile: "chafa/glib/gosxutils.m".}

  {.compile: "chafa/glib/libcharset/localcharset.c".}

  {.compile: "chafa/glib/gnulib/asnprintf.c".}
  {.compile: "chafa/glib/gnulib/frexp.c".}
  {.compile: "chafa/glib/gnulib/frexpl.c".}
  #{.compile: "chafa/glib/gnulib/isinf.c".}
  #{.compile: "chafa/glib/gnulib/isnan.c".}
  {.compile: "chafa/glib/gnulib/isnand.c".}
  {.compile: "chafa/glib/gnulib/isnanf.c".}
  {.compile: "chafa/glib/gnulib/isnanl.c".}
  {.compile: "chafa/glib/gnulib/printf-args.c".}
  {.compile: "chafa/glib/gnulib/printf-frexp.c".}
  {.compile: "chafa/glib/gnulib/printf-frexpl.c".}
  {.compile: "chafa/glib/gnulib/printf-parse.c".}
  {.compile: "chafa/glib/gnulib/printf.c".}
  {.compile: "chafa/glib/gnulib/signbitd.c".}
  {.compile: "chafa/glib/gnulib/signbitf.c".}
  {.compile: "chafa/glib/gnulib/signbitl.c".}
  {.compile: "chafa/glib/gnulib/vasnprintf.c".}
  {.compile: "chafa/glib/gnulib/xsize.c".}

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
else:
  proc imageToAnsi*(image: string, outWidth: cint): string =
    raise newException(Exception, "Image import not supported on this platform")
