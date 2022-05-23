#include <emscripten.h>

EM_JS(void, ansiwave_browse_file, (const char* callback), {
  var elem = document.createElement("input");
  elem.type = "file";
  var importImage = function(e) {
    var file = e.target.files[0];
    var reader = new FileReader();

    reader.onload = function(e) {
      // convert response to an array
      var bytes = new Uint8Array(e.target.result);

      var arrayOnWasmHeap = _malloc(bytes.byteLength);
      writeArrayToMemory(bytes, arrayOnWasmHeap);

      // call c function
      Module.ccall(UTF8ToString(callback), null, ['string', 'number', 'number'], [file.name, arrayOnWasmHeap, bytes.byteLength]);

      // sometimes the mouse can get "stuck" in a mousedown state because mouseup
      // is not sent due to the dialog box, so manually send it.
      Module.ccall("onMouseUp", null, ['number', 'number'], [0, 0]);
    };
    if (file instanceof File) {
      reader.readAsArrayBuffer(file);
    }
    elem.value = '';
  };
  elem.addEventListener('change', importImage);
  elem.click();
});

EM_JS(void, ansiwave_start_download, (const char* data_uri, const char* filename), {
  var elem = document.createElement("a");
  elem.href = UTF8ToString(data_uri);
  elem.download = UTF8ToString(filename);
  elem.click();
});

EM_JS(int, ansiwave_localstorage_set, (const char* key, const char* val), {
  try {
    window.localStorage.setItem(UTF8ToString(key), UTF8ToString(val));
    return 1;
  } catch (e) {
    return 0;
  }
});

EM_JS(char*, ansiwave_localstorage_get, (const char* key), {
  var val = window.localStorage.getItem(UTF8ToString(key));
  if (val == null) {
    val = "";
  }
  var lengthBytes = lengthBytesUTF8(val)+1;
  var stringOnWasmHeap = _malloc(lengthBytes);
  stringToUTF8(val, stringOnWasmHeap, lengthBytes);
  return stringOnWasmHeap;
});

EM_JS(void, ansiwave_localstorage_remove, (const char* key), {
  window.localStorage.removeItem(UTF8ToString(key));
});

EM_JS(char*, ansiwave_localstorage_list, (), {
  var arr = [];
  Object.keys(localStorage).forEach(function(key){
    arr.push(key);
  });
  var json = JSON.stringify(arr);
  var lengthBytes = lengthBytesUTF8(json)+1;
  var stringOnWasmHeap = _malloc(lengthBytes);
  stringToUTF8(json, stringOnWasmHeap, lengthBytes);
  return stringOnWasmHeap;
});

EM_JS(void, ansiwave_play_audio, (const char* src), {
  try {
    ansiwaveAudio.pause();
  } catch (e) {}
  try {
    ansiwaveAudio = new Audio(UTF8ToString(src));
    ansiwaveAudio.play();
  } catch (e) {
    console.error(e);
  }
});

EM_JS(void, ansiwave_stop_audio, (), {
  try {
    ansiwaveAudio.pause();
  } catch (e) {
    console.error(e);
  }
});
