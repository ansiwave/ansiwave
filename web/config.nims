when defined(release):
  switch("define", "defaultGetAddress:")
  switch("define", "defaultPostAddress:https://post.ansiwave.net")
  switch("define", "defaultBoard:kEKgeSd3-74Uy0bfOOJ9mj0qW3KpMpXBGrrQdUv190E")
else:
  switch("define", "defaultGetAddress:")
  switch("define", "defaultPostAddress:")
  switch("define", "defaultBoard:Q8BTY324cY7nl5kce6ctEfk8IRIrtsM8NfKL29B-3UE")

--define:emscripten

--nimcache:tmp # Store intermediate files close by in the ./tmp dir.

--os:linux # Emscripten pretends to be linux.
--cpu:wasm32 # Emscripten is 32bits.
--cc:clang # Emscripten is very close to clang, so we ill replace it.
when defined(windows):
  --clang.exe:emcc.bat  # Replace C
  --clang.linkerexe:emcc.bat # Replace C linker
  --clang.cpp.exe:emcc.bat # Replace C++
  --clang.cpp.linkerexe:emcc.bat # Replace C++ linker.
else:
  --clang.exe:emcc  # Replace C
  --clang.linkerexe:emcc # Replace C linker
  --clang.cpp.exe:emcc # Replace C++
  --clang.cpp.linkerexe:emcc # Replace C++ linker.
--listCmd # List what commands we are running so that we can debug them.

--gc:orc # GC:orc is friendlier with crazy platforms.
--exceptions:goto # Goto exceptions are friendlier with crazy platforms.
--define:noSignalHandler # Emscripten doesn't support signal handlers.

--define:useMalloc
--opt:size
--threads:off

# Pass this to Emscripten linker to generate html file scaffold for us.
when defined(emscripten_worker):
  switch("passL", "-o build/worker.js -s -s EXPORTED_FUNCTIONS=\"['_main','_recvAction']\" -s ALLOW_MEMORY_GROWTH=1 -s BUILD_AS_WORKER")
else:
  switch("passL", "-o build/index.html -s -s EXPORTED_FUNCTIONS=\"['_main','_insertFile', '_insertPrivateKey', '_hashChanged', '_onMouseDown', '_onMouseMove', '_onMouseUp', '_onScrollDown', '_onScrollUp', '_onScroll']\" -s EXPORTED_RUNTIME_METHODS=\"['ccall']\" -s ALLOW_MEMORY_GROWTH=1 --shell-file shell_minimal.html")

--define:chafa

when defined(emscripten_worker):
  --define:staticSqlite
