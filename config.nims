when defined(linux):
  when defined(musl):
    --dynlibOverride:curl
    switch("passL", "-static libcurl.a libssl.a libcrypto.a")
    switch("gcc.exe", "musl-gcc")
    switch("gcc.linkerexe", "musl-gcc")
    # building openssl statically:
    # export CC="musl-gcc -static -idirafter /usr/include/ -idirafter /usr/include/x86_64-linux-gnu/"
    # export LD="musl-gcc"
    # ./Configure no-async no-hw no-zlib no-pic no-dso no-threads linux-x86_64
    # make
    #
    # building curl statically:
    # ./configure --disable-shared --enable-static --with-openssl=/usr/local CC="musl-gcc" LD="musl-gcc"
    # make
  else:
    switch("passL", "-ldl -lm -lpthread")
elif defined(windows):
  switch("passL", "-static")

--threads:on
--define:staticSqlite
--define:multiplexSqlite
