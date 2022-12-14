This is the web version of [ANSIWAVE BBS](https://github.com/ansiwave/ansiwave_bbs).

If you want to build this for your own ANSIWAVE instance, you should definitely change the defaults that are set in [config.nims](config.nims). The `defaultPostAddress` should just be blank unless you want new posts to be sent to a different server than the one hosting the frontend files. The `defaultBoard` should be the public key of the main board on your server.

To make a release build, [install Nim](https://nim-lang.org/install.html) and do:

```
nimble emscripten
```

NOTE: You must install Emscripten first:

```
git clone https://github.com/emscripten-core/emsdk
cd emsdk
./emsdk install latest
./emsdk activate latest
# add the dirs that are printed by the last command to your PATH
```
