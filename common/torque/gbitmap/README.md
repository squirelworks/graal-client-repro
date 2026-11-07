# gbitmap

**Stock** TGE. `GBitmap` and, on builds that still have it, the OpenGL texture manager.

What it has to do later: read the image formats those binaries already call (PNG, and the JPEG / JPEG 2000 / DDS readers the 4.x engine exports). It does not draw tiles. Tile pixels leave through the host callbacks, which are the launcher, not this unit.

| Version | Linked? |
|---|---|
| 3.04 | Yes. Texture manager and `GBitmap`, including the PNG reader on the TGE source path. |
| 3.153 | Yes. |
| 4.04r2 3D | Yes. Marker scan hits `GBitmap` and the texture manager. |
| 4.2.0.8 launcher | No. |
| 4.2.0.8 engine | Yes. Marker scan hits `GBitmap` on `GraalEngine.dll`. The texture manager string is not in that 2D DLL. |
| 4.2.0.8 3D | Not on the list. `torque/4208-g3d.md` does not name `GBitmap`. |
| 5.0.0.7 launcher | No. |
| 5.0.0.7 engine | Yes. The note names `GBitmap`. |
| 5.0.0.7 3D | Yes. The note names `GBitmap`. |
| 5.30 / 5.31 | No. Not named among the GUI strings that remain. |
| 6.x | No. Unpacked 6.00 has its own image readers inside `quattro_lib`, not this class. |
