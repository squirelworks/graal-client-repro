# host4208

A 4.2.0.8-shaped host for the residual Torque surface in the engine DLL.
The language is C++. The Pascal module list under `common/torque/` is
unchanged. This directory is not a FreePascal unit, and it is not the
Delphi launcher in `graal-4.20r8-G3D20126`.

The 4.2.0.8 engine has no Torque console, no `SimObject` and no `.dso`.
`scripts/level-tile.cs` is a provisional line script: it opens a
`TServerLevel` and places one tile. `Shell420` in the client folder is
the Delphi shell that starts this program.

## Build and run

`scripts/build.sh graal-4.20r8-G3D20126` runs this Makefile and the Delphi shell. From this directory, with the system compiler (`g++` or `clang++`) and zlib:

```
make
./build/host4208
./build/host4208 --port 14900
```

The default address is loopback. The default port is the lab port 14900.
A host that does not resolve to loopback is refused, and nothing is sent.
If nothing is listening, the program still prints the frame and exits 0.

## What is real, and what is provisional

| Item | Status |
|---|---|
| Token `G3D20126` | The documented game-server token for Windows 4.20r8 (`protocol/v4x-clients.md`). The original assembles it one character at a time, so the image has no string literal. This host sends that row. |
| Residual types | `GuiCanvas`, `GuiControl`, `Point2I`, `GBitmap`, plus the engine types `GuiGraalCtrl` and `GuiGraal3DCtrl`. From the engine manifest. |
| Engine controls | The 2D `GuiControl` tree and the 3D plugin classes, including `GuiGraalCtrl` as the level view. |
| `new GuiGraalCtrl` | Discarded. The note says the script builder does not construct that type. |
| `setContentControl(MainMenuGui2D)` | The note's content switch when setup passes. |
| `Point2I` size | Not recovered. The name is registered and no size is invented. |
| `GBitmap` pixels | Not drawn. The DLL calls out to the launcher for pixels. |
| First frame | Login line alone, plain zlib, no compression byte. Shape from `tests/Test420.dpr`: id 5, key, token, account, password, `win,"","",""`. |
| Machine fields | Provisional against a real PC. The three hashes are empty, as in that test. A real client fills them. |
| Ids 37 and 23 | The next messages in that test, in later gen-5 frames. Not sent here. |
| TorqueScript | Absent. Not run. |

Packet id in the first frame is 5. No unknown packet id is sent.

The version-specific frame builder uses ../shared/first_frame.cpp for framing and loopback transport.

## Shared first-frame component

The plain first-frame builder remains version-specific in src/login.cpp.
Compression, framing and loopback sending come from ../shared/first_frame.cpp.
Run make test for independent byte/decoding checks and a local TCP fixture.
These checks establish first-frame delivery only, not login or gameplay.
