{.compile: "libclipboard/clipboard_common.c".}
{.compile: "libclipboard/options.c".}
when defined(macosx):
  {.compile: "libclipboard/clipboard_cocoa.c".}
  {.passC: "-DLIBCLIPBOARD_BUILD_COCOA -x objective-c".}
  {.passL: "-framework Cocoa".}
elif defined(windows):
  {.compile: "libclipboard/clipboard_win32.c".}
  {.passC: "-DLIBCLIPBOARD_BUILD_WIN32".}
elif defined(linux):
  {.compile: "libclipboard/clipboard_x11.c".}
  {.passC: "-DLIBCLIPBOARD_BUILD_X11".}
  {.passL: "-lxcb".}

type
  clipboard_c* {.bycopy.} = object
  clipboard_opts* {.bycopy.} = object
  clipboard_mode* = enum
    LCB_CLIPBOARD = 0,
    LCB_PRIMARY,
    LCB_SECONDARY,
    LCB_MODE_END

proc clipboard_init_options*(): ptr clipboard_opts {.cdecl, importc.}
proc free*(p: pointer) {.cdecl, importc.}

## *
##   \brief Instantiates a new clipboard instance of the given type.
##
##   \param [in] cb_opts Implementation specific options (optional).
##   \return The new clipboard instance, or NULL on failure.
##
proc clipboard_new*(cb_opts: ptr clipboard_opts): ptr clipboard_c {.cdecl, importc.}

## *
##   \brief Frees associated clipboard data from the provided structure.
##
##   \param [in] cb The clipboard to be freed.
##
proc clipboard_free*(cb: ptr clipboard_c) {.cdecl, importc.}

## *
##   \brief Clears the contents of the given clipboard.
##
##   \param [in] cb The clipboard to clear.
##   \param [in] mode Which clipboard to clear (platform dependent)
##
proc clipboard_clear*(cb: ptr clipboard_c; mode: clipboard_mode) {.cdecl, importc.}

## *
##   \brief Determines if the clipboard is currently owned
##
##   \param [in] cb The clipboard to check
##   \param [in] mode Which clipboard to clear (platform dependent)
##   \return true iff the clipboard data is owned by the provided instance.
##
proc clipboard_has_ownership*(cb: ptr clipboard_c; mode: clipboard_mode): bool {.cdecl, importc.}

## *
##   \brief Retrieves the text currently held on the clipboard.
##
##   \param [in] cb The clipboard to retrieve from
##   \param [out] length Returns the length of the retrieved data, excluding
##                       the NULL terminator (optional).
##   \param [in] mode Which clipboard to clear (platform dependent)
##   \return A copy to the retrieved text. This must be free()'d by the user.
##           Note that the text is encoded in UTF-8 format.
##
proc clipboard_text_ex*(cb: ptr clipboard_c; length: ptr cint; mode: clipboard_mode): cstring {.cdecl, importc.}

## *
##   \brief Simplified version of clipboard_text_ex
##
##   \param [in] cb The clipboard to retrieve from
##   \return As per clipboard_text_ex.
##
##   \details This function assumes LCB_CLIPBOARD as the clipboard mode.
##
proc clipboard_text*(cb: ptr clipboard_c): cstring {.cdecl, importc.}

## *
##   \brief Sets the text for the provided clipboard.
##
##   \param [in] cb The clipboard to set the text.
##   \param [in] src The UTF-8 encoded text to be set in the clipboard.
##   \param [in] length The length of text to be set (excluding the NULL
##                      terminator).
##   \param [in] mode Which clipboard to clear (platform dependent)
##   \return true iff the clipboard was set (false on error)
##
##   \details If the length parameter is -1, src is treated as a NULL-terminated
##            string and its length will be determined automatically.
##
proc clipboard_set_text_ex*(cb: ptr clipboard_c; src: cstring; length: cint;
                           mode: clipboard_mode): bool {.cdecl, importc.}

## *
##   \brief Simplified version of clipboard_set_text_ex
##
##   \param [in] cb The clipboard to set the text.
##   \param [in] src The UTF-8 encoded NULL terminated string to be set.
##   \return true iff the clipboard was set (false on error)
##
##   \details This function assumes LCB_CLIPBOARD as the clipboard mode.
##
proc clipboard_set_text*(cb: ptr clipboard_c; src: cstring): bool {.cdecl, importc.}

