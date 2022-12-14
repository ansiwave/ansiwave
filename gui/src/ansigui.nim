from wavecorepkg/db/vfs import nil
vfs.register()

from ./gui import nil
when isMainModule:
  gui.main()

