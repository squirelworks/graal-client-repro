# host304

A 3.04-shaped host that boots, runs one TorqueScript file, and sends a
login-shaped first frame at loopback. The language is C++. The Pascal
module list under `common/torque/` is unchanged, and this directory is
not a FreePascal unit.

This is not a Torque console. It does not execute `main.cs`, it does not
load `.dso` files, and it does not simulate the stock sim set. Unknown
`GuiGraalCtrl` bodies log the call and return.

## Build and run

From this directory, with the system compiler (`g++` or `clang++`) and zlib:

```
make
./build/host304
./build/host304 --port 14802
CXX=clang++ make clean all
```

The default address is loopback. The default port is the lab port 14802.
A host that does not resolve to loopback is refused, and nothing is sent.
If nothing is listening, the program still prints the frame and exits 0.

The script is `scripts/camera-move.cs`. It creates a camera and runs one
move. `Adventure.moveUp(1)` hits the registered control so the stub logs.

## What is real, and what is provisional

| Item | Status |
|---|---|
| Token `G3D03014` | The folder name, and the game-server token the 3.04 lab saw. Not provisional. |
| `GuiGraalCtrl` method names and argument counts | From `torque/engine-304.md`, same table as `TorqueHost304.pas`. |
| `GuiGraalCtrl` method bodies | Unknown. Stubs that compile and log the call. |
| `Camera.setTransform` | Provisional name. The 3.04 note says `Camera` has three methods and does not name them. The runner applies the first three numbers as the position and logs the move. |
| First-frame message list | Lab note: one plain zlib frame, no compression byte, messages 5 (login), 37 (`English`), 34 `bigmap.txt`, 34 `minimap.txt`. |
| Id 34 filename prefix | Provisional. Five-byte GINT5 zero, copied from `tests/Test304.dpr` ("no cached mod time"). The lab note names the files and does not print those bytes. This is not a new wire map. |
| Cipher key | Lab fixed at 1 unless `--key` is set. The client draws a key in 0..127. |
| Console | A line runner for this file. Not the stock console. |

Packet ids in the frame are 5, 37 and 34. No unknown packet id is sent.
