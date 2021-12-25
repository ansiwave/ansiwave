when defined(linux):
  when defined(musl):
    --dynlibOverride:curl
    switch("passL", "-static libcurl.a libssl.a libcrypto.a")
    switch("gcc.exe", "musl-gcc")
    switch("gcc.linkerexe", "musl-gcc")
  else:
    switch("passL", "-ldl -lm -lpthread")

--threads:on
--define:staticSqlite
--define:multiplexSqlite
