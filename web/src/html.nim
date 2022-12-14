from htmlparser import nil
from xmltree import `$`, `[]`
from strutils import format

proc parseRgb(rgb: string, output: var tuple[r: int, g: int, b: int]): bool =
  let parts = strutils.split(rgb, {'(', ')'})
  if parts.len >= 2:
    let
      cmd = strutils.strip(parts[0])
      args = strutils.strip(parts[1])
    if cmd == "rgba" or cmd == "rgb":
      let colors = strutils.split(args, ',')
      if colors.len >= 3:
        try:
          let
            r = strutils.parseInt(strutils.strip(colors[0]))
            g = strutils.parseInt(strutils.strip(colors[1]))
            b = strutils.parseInt(strutils.strip(colors[2]))
          output = (r, g, b)
          return true
        except Exception as ex:
          discard
  false

proc fgToAnsi(color: string): string =
  case color:
  of "black":
    "\e[30m"
  of "red":
    "\e[31m"
  of "green":
    "\e[32m"
  of "yellow":
    "\e[330m"
  of "blue":
    "\e[34m"
  of "magenta":
    "\e[35m"
  of "cyan":
    "\e[36m"
  of "white":
    "\e[37m"
  else:
    var rgb: tuple[r: int, g: int, b: int]
    if parseRgb(color, rgb):
      "\e[38;2;$1;$2;$3m".format(rgb[0], rgb[1], rgb[2])
    else:
      ""

proc bgToAnsi(color: string): string =
  case color:
  of "black":
    "\e[40m"
  of "red":
    "\e[41m"
  of "green":
    "\e[42m"
  of "yellow":
    "\e[43m"
  of "blue":
    "\e[44m"
  of "magenta":
    "\e[45m"
  of "cyan":
    "\e[46m"
  of "white":
    "\e[47m"
  else:
    var rgb: tuple[r: int, g: int, b: int]
    if parseRgb(color, rgb):
      "\e[48;2;$1;$2;$3m".format(rgb[0], rgb[1], rgb[2])
    else:
      ""

proc toAnsi*(node: xmltree.XmlNode): string =
  var
    fg: string
    bg: string
  case xmltree.kind(node):
  of xmltree.xnVerbatimText, xmltree.xnElement:
    case xmltree.tag(node):
    of "span":
      let
        style = xmltree.attr(node, "style")
        statements = strutils.split(style, ';')
      for statement in statements:
        let parts = strutils.split(statement, ':')
        if parts.len == 2:
          let
            key = strutils.strip(parts[0])
            val = strutils.strip(parts[1])
          if key == "color":
            fg = fgToAnsi(val)
          elif key == "background-color":
            bg = bgToAnsi(val)
    else:
      discard
  else:
    discard
  let colors = fg & bg
  if colors.len > 0:
    result &= colors
  for i in 0 ..< xmltree.len(node):
    result &= toAnsi(node[i])
  if colors.len > 0:
    result &= "\e[0m"
  case xmltree.kind(node):
  of xmltree.xnText:
    result &= xmltree.innerText(node)
  of xmltree.xnVerbatimText, xmltree.xnElement:
    case xmltree.tag(node):
    of "div":
      result &= "\n"
    else:
      discard
  else:
    discard

proc toAnsi*(html: string): string =
  result = toAnsi(htmlparser.parseHtml(html))
  if strutils.endsWith(result, "\n"):
    result = result[0 ..< result.len-1]
