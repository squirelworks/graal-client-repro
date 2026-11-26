# Sources

| Path | What it holds |
|---|---|
| `main.cpp` | Arguments, the window (`common/cpp/quattro/draw`: Win32, AppKit or X11, else headless), the 50 ms loop. |
| `host6037/` | `Frank::Host`: the 6.03r7 `Shell::Program` and the `3 ` path (strip the marker, open the link on port + 1, then the TCP login; a 178 warp to a `3 ` server does the same). `ViewWindow` puts the 3D view over the frame. |
| `graal3d5120/` | The 3D view: the 5.12 repro's renderer (black until a Camera is named, as the 5.12). v5.120 is 5.12: the link and world are the 5.12 repro's (`common/cpp/graal3dengine`, used by `graal-5.12-G3D14097` and `graal-5.12mac-G3D15097`). |
| `net/udp/` | `Frank::Link3D`: the 5.12 link on a UDP socket, left enabled in a 6.x host. |
| `platform/` | Notes per platform. |

The engine is the Quattro program, with no modern Torque3D base.
