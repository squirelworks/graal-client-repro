# host304

A 3.04-shaped host that boots, runs one TorqueScript file, and sends a
login-shaped first frame at loopback. The language is C++. The Pascal
module list under `common/torque/` is unchanged, and this directory is
not a FreePascal unit.

This is not a Torque console. It does not execute `main.cs`, it does not
load `.dso` files, and it does not simulate the stock sim set. Unknown
`GuiGraalCtrl` bodies log the call and return.

## Build and run

`scripts/build.sh graal-3.04-G3D03014` runs this Makefile. From this directory, with the system compiler (`g++` or `clang++`) and zlib:

```
make
./build/host304
./build/host304 --port 14802
CXX=clang++ make clean all
```

The default address is loopback. The default port is the lab port 14802.
A host that does not resolve to loopback is refused, and nothing is sent.
If nothing is listening, the program still prints the frame and exits 0.

The script is `scripts/camera-move.cs`. It opens the play GUI
(`Canvas.setContent(AdventureGui)`), so the log says the level view
opened, then creates a camera and runs one move. `moveMap` holds the
script-bound keys. Hardcoded key bytes stay in `GuiGraalCtrl`.
`Adventure.moveUp(1)` hits the registered control so the stub logs.

## What is real, and what is provisional

| Item | Status |
|---|---|
| Token `G3D03014` | The folder name, and the game-server token the 3.04 lab saw. Not provisional. |
| `GuiGraalCtrl` method names and argument counts | From the 3.04 GUI notes, same console table as `TorqueHost304.pas`. |
| Registered controls | The 3.04 class-rep list, including `GuiGraalCtrl` as the level view and `GuiControlProfile`. Demo HUD classes are registered and not instanced. |
| `GuiGraalCtrl` method bodies | Stubs. Each comment says what the call should do. |
| Input | Arrows, A/S/D/Q/P/M, T, and the function keys are script binds. Key byte 2, the emoticon modifier band, and key byte `0x19` with modifier `0x30` are hardcoded on the control. |
| `Camera.setTransform` | The runner applies the first three numbers as the position and logs the move. The 3.04 note says `Camera` has three methods and does not name them. |
| First-frame message list | Lab note: one plain zlib frame, no compression byte, messages 5 (login), 37 (`English`), 34 `bigmap.txt`, 34 `minimap.txt`. |
| Id 34 filename prefix | Provisional. Five-byte GINT5 zero, copied from `tests/Test304.dpr` ("no cached mod time"). The lab note names the files and does not print those bytes. This is not a new wire map. |
| Cipher key | Lab fixed at 1 unless `--key` is set. The client draws a key in 0..127. |
| Console | A line runner for this file. Not the stock console. |

Packet ids in the frame are 5, 37 and 34. No unknown packet id is sent.
