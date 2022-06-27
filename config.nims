when defined(release):
  switch("define", "defaultGetAddress:https://bbs.ansiwave.net/bbs/")
  switch("define", "defaultPostAddress:https://post.ansiwave.net")
  switch("define", "defaultBoard:kEKgeSd3-74Uy0bfOOJ9mj0qW3KpMpXBGrrQdUv190E")
else:
  switch("define", "defaultGetAddress:http://localhost:3000")
  switch("define", "defaultPostAddress:http://localhost:3000")
  switch("define", "defaultBoard:Q8BTY324cY7nl5kce6ctEfk8IRIrtsM8NfKL29B-3UE")

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
--gc:orc

