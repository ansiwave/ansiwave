when defined(linux):
  when defined(musl):
    switch("passL", "-static")
    switch("gcc.exe", "musl-gcc")
    switch("gcc.linkerexe", "musl-gcc")
  else:
    switch("passL", "-ldl -lm -lpthread")
