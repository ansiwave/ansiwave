{.compile: "qrcodegen/qrcodegen.c".}

##
##  The error correction level in a QR Code symbol.
##

type
  qrcodegen_Ecc* = enum ##  Must be declared in ascending order of error protection
                        ##  so that an internal qrcodegen function works properly
    qrcodegen_Ecc_LOW = 0,    ##  The QR Code can tolerate about  7% erroneous codewords
    qrcodegen_Ecc_MEDIUM,     ##  The QR Code can tolerate about 15% erroneous codewords
    qrcodegen_Ecc_QUARTILE,   ##  The QR Code can tolerate about 25% erroneous codewords
    qrcodegen_Ecc_HIGH        ##  The QR Code can tolerate about 30% erroneous codewords


##
##  The mask pattern used in a QR Code symbol.
##

type
  qrcodegen_Mask* = enum ##  A special value to tell the QR Code encoder to
                         ##  automatically select an appropriate mask pattern
    qrcodegen_Mask_AUTO = -1,   ##  The eight actual mask patterns
    qrcodegen_Mask_0 = 0, qrcodegen_Mask_1, qrcodegen_Mask_2, qrcodegen_Mask_3,
    qrcodegen_Mask_4, qrcodegen_Mask_5, qrcodegen_Mask_6, qrcodegen_Mask_7

# The worst-case number of bytes needed to store one QR Code

const qrcodegen_VERSION_MIN* = 1
const qrcodegen_VERSION_MAX* = 40
const qrcodegen_BUFFER_LEN_MAX* = 3918


## ---- Functions (high level) to generate QR Codes ----
##
##  Encodes the given text string to a QR Code, returning true if encoding succeeded.
##  If the data is too long to fit in any version in the given range
##  at the given ECC level, then false is returned.
##  - The input text must be encoded in UTF-8 and contain no NULs.
##  - The variables ecl and mask must correspond to enum constant values.
##  - Requires 1 <= minVersion <= maxVersion <= 40.
##  - The arrays tempBuffer and qrcode must each have a length of at least
##    qrcodegen_BUFFER_LEN_FOR_VERSION(maxVersion), and cannot overlap.
##  - After the function returns, tempBuffer contains no useful data.
##  - If successful, the resulting QR Code may use numeric,
##    alphanumeric, or byte mode to encode the text.
##  - In the most optimistic case, a QR Code at version 40 with low ECC
##    can hold any UTF-8 string up to 2953 bytes, or any alphanumeric string
##    up to 4296 characters, or any digit string up to 7089 characters.
##    These numbers represent the hard upper limit of the QR Code standard.
##  - Please consult the QR Code specification for information on
##    data capacities per version, ECC level, and text encoding mode.
##

proc qrcodegen_encodeText*(text: cstring; tempBuffer: pointer;
                           qrcode: pointer; ecl: qrcodegen_Ecc; minVersion: cint;
                           maxVersion: cint; mask: qrcodegen_Mask; boostEcl: bool): bool {.importc.}

##
##  Returns the side length of the given QR Code, assuming that encoding succeeded.
##  The result is in the range [21, 177]. Note that the length of the array buffer
##  is related to the side length - every 'uint8_t qrcode[]' must have length at least
##  qrcodegen_BUFFER_LEN_FOR_VERSION(version), which equals ceil(size^2 / 8 + 1).
##

proc qrcodegen_getSize*(qrcode: pointer): cint {.importc.}

##
##  Returns the color of the module (pixel) at the given coordinates, which is false
##  for light or true for dark. The top left corner has the coordinates (x=0, y=0).
##  If the given coordinates are out of bounds, then false (light) is returned.
##

proc qrcodegen_getModule*(qrcode: pointer; x: cint; y: cint): bool {.importc.}


proc printQr*(qrcode: pointer) =
  let size = qrcodegen_getSize(qrcode)
  let border = 4'i32
  for y in -border ..< size + border:
    for x in -border ..< size + border:
      stdout.write((if qrcodegen_getModule(qrcode, x, y): "██" else: "  "))
    stdout.write("\n")
  stdout.write("\n")

