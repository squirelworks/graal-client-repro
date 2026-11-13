# The C++ hosts: files, token, messages and platforms (#152)

This file records what each C++ host builds from and what it sends, read from the source on `main` (2026-11-12). It covers #152's "verify and document the actual shared-module files and each host's explicit token/message/platform profile". Each fact links to the file that sets it. Anything the source marks provisional is listed as provisional here.

The hosts are separate from the Pascal module stubs and from `manifests/*.list`. A host links none of the `Tq*.pas` units, and no manifest names a host.

## Shared module files

| File | Used by | What it is |
|---|---|---|
| `shared/first_frame.cpp`, `shared/first_frame.hpp` | host304, host4208 | The first-frame codec (zlib member, u16be length) and the loopback lab transport (`HostNet::sendLoginFrame`). An empty host means loopback; a resolved non-loopback address is rejected and nothing is sent. Winsock is started before the hostname lookup on Windows. |
| `shared/tests/first_frame_test.cpp` | both `make test` | The codec test. Built with `-DPROFILE304` for host304 and without it for host4208, so each host's own version adapter (`src/login.cpp`) is the one under test. |
| `shared/tests/loopback_test.py` | both `make test` | Starts the host against a loopback listener and checks the bytes received (`loopback_test.py <host> 304` or `4208`). |

Nothing else is shared. Each host has its own copy of `controls`, and the frame builder is per host (`src/login.cpp`).

## host304 (3.04 Linux monolith shape)

| | |
|---|---|
| Sources | `src/main.cpp`, `src/guigraal.cpp`, `src/controls.cpp`, `src/input.cpp`, `src/script.cpp`, `src/login.cpp` + shared ([Makefile](host304/Makefile)) |
| Token | `G3D03014` ([src/login.cpp](host304/src/login.cpp)). Not provisional: Graal_analysis `protocol/v3x-clients.md`, confirmed on the wire in `version-profiles/lab-304-linux-2026-10-30.md` ([src/login.hpp](host304/src/login.hpp)). |
| First frame | One plain zlib frame, no compression byte, no XOR, with messages 5 (login: GCHAR id, GCHAR key, token, GSTRING account and password), 37 (raw language), 34 `bigmap.txt`, 34 `minimap.txt`, separated by newlines. Same encoding `graal-3.04-G3D03014/tests/Test304.dpr` asserts. |
| Provisional | The five-byte GINT5(0) before each id-34 filename ("no cached mod time"). The lab note names the files but not those bytes. |
| Script | Runs one TorqueScript file line by line ([src/script.cpp](host304/src/script.cpp)). It is not the TGE console: no `main.cs`, no `.dso`, no stock sim set. Unknown `GuiGraalCtrl` bodies log and return. |
| Platforms | Linux and macOS (system C++ and zlib), Windows (MSYS2/MinGW, `-lws2_32`). The `cpp-hosts` workflow builds and tests on ubuntu-latest, macos-latest and windows-latest. |

## host4208 (4.2.0.8 engine DLL shape)

| | |
|---|---|
| Sources | `src/main.cpp`, `src/surface.cpp`, `src/controls.cpp`, `src/login.cpp` + shared ([Makefile](host4208/Makefile)) |
| Token | `G3D20126` (`kVersionToken`, [src/login.cpp](host4208/src/login.cpp)): the documented Windows 4.20r8 game-server token (`protocol/v4x-clients.md`). The original builds it one character at a time, so its image has no string literal. |
| First frame | The login line alone: plain zlib, no compression byte, id 5, key, token, account, password, then `win` and three machine fields. Same encoding `graal-4.20r8-G3D20126/tests/Test420.dpr` asserts. Ids 37 and 23 follow in later gen-5 frames, which this host does not send. |
| Machine fields | The real client sends three machine hashes; this host sends the test's made-up ones (MD5 hex of three Squirrel-themed strings). |
| Script | None. The 4.2.0.8 engine has no Torque console, no `SimObject` and no `.dso`. `scripts/level-tile.cs` is a provisional line script that opens a `TServerLevel` and places one tile. |
| Platforms | As host304. On Windows, `Shell420` in `graal-4.20r8-G3D20126` (Delphi) is the program that starts this host. |

## Unsupported, by design or not yet

- No host executes `.dso` files, and no host links the DSO reader, the VM or the native registry under `console/`. Those components build and test on their own (`torque-dso`, `torque-vm`, `torque-native` workflows).
- No GUI is drawn. Neither host opens a window or renders a canvas.
- No host sends anything past its first frame, and none connects outside loopback.
- 4.04r2, 5.0.0.7 and 3.153 have manifests but no host.
- Runtime work stays under #172 (first DSO execution and object slice) and #173 (GS2).
