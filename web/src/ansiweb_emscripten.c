#include <emscripten.h>

EM_JS(int, ansiweb_get_cursor_line, (const char* selector), {
  var elem = document.querySelector(UTF8ToString(selector));
  if (!elem) return;

  function uuidv4() {
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
      var r = Math.random() * 16 | 0, v = c == 'x' ? r : (r & 0x3 | 0x8);
      return v.toString(16);
    });
  }

  var selection = document.getSelection();
  if (selection.rangeCount < 1) {
    return -1;
  }
  var range = selection.getRangeAt(0);
  range.collapse(true);
  var span = document.createElement('span');
  var id = uuidv4();
  span.appendChild(document.createTextNode(id));
  range.insertNode(span);

  var text = elem.innerText;
  var newLines = 0;
  var lastNewline = null;
  for (var i = 0; i < text.length; i++) {
    if (text[i] == '\n' && lastNewline != i - 1) {
      newLines += 1;
      lastNewline = i;
    } else {
      if (text.substring(i).startsWith(id)) break;
    }
  }

  span.remove();
  return newLines;
});
