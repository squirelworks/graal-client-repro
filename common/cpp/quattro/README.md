# common/cpp/quattro: the Quattro program

The late-5 and 6.x clients are not Torque. From 5.24 on, every Windows,
Linux and Mac build is one native C++ program whose source paths say
`quattro_lib` and whose play name is `Quattro_Play`. This directory
rebuilds that program, in C++, for the folders that run it. It is the
"separate own-engine track" of
[#109](https://github.com/squirelworks/graal-client-repro/issues/109), and
Track D of the v3-to-v6 plan: the shared GS2 script machine is Track B, in
`common/cpp/gs2/`, and this program hosts it.

No original code is in here. Behaviour comes from the Graal_analysis notes
named in each file's header, which tag their evidence.

## What the original program is

Read from Graal_analysis `client-internals/engine-600r2.md`,
`client-internals/unpacked-6037.md`, `client-internals/issho-cut.md` and
`protocol/v6x-clients.md`:

- **Drawing.** OpenGL presents the frame (Direct3D 9 is only a capability
  check on Windows). The world is drawn in named passes (`Game_Draw`,
  `Game_Draw_GetDrawObjects`, `Game_Draw_Player`, `Game_Draw_Texts`,
  `Draw_Tiles`, `Draw_ShowImg`, `Draw_Particles`), then the GUI
  (`RenderGUI`, one `Draw_*` routine per control type).
- **GUI.** GS2 controls with Torque's names (`GuiWindowCtrl`,
  `GuiScrollCtrl`, `GuiMLTextCtrl`, ...) and Graal's own
  (`GuiGraalCtrl` playfield, `GuiShowImgCtrl`, PM, start menu). Every
  shell dialog is a script: `StartScript_Profiles`,
  `StartScript_GraalGui`, `StartScript_MessageBoxDialog`,
  `StartScript_SetupDialog`, `StartScript_SelectFileDialog`, the connect
  message. The server list and account screens come from the Login
  server's scripts.
- **Script.** The GS2 machine on `TGraalVar` values, the `TServer*` world
  objects, classes and joins, and the `GRESCR01` script cache.
- **Network.** `TSocket` with the gen-5 codec. No Torque connection, no UDP.
- **Files.** Levels `GR-V1.03` to `GR-V1.05` (6.00 also reads 1.00 to
  1.02), `GRPKG001` packages, the `weblevels` caches, PNG/GIF/JPEG.
- **Sound.** FMOD (SDL_mixer on Linux).

Seihai's Issho plays 6.x through its own flat loop and does not try to be
this program. This directory does.

## Layout

| Directory | Original piece | State |
|---|---|---|
| `net/` | `TSocket`, the game connection, the session | **done**: wire integers, gen-5 codec (6.x long frames, raw-data escape), build rows, socket, connection, 178 warp |
| `cache/` | `weblevels` script cache | **done**: DES with Graal's key twist, CRC32, `GRESCR01` read and write |
| `tools/` | (none) | `quattro-session`, a headless lab tool that logs a session |
| `draw/` | the draw passes and the window | next: software frame buffer, X11 presenter and headless mode, the world passes |
| `files/` | levels and packages | next: `GR-V1.03`–`1.05` for the playfield |
| `shell/` | the program loop, `StartScript_*`, `GuiGraalCtrl` | after `common/cpp/gs2` lands: the script host wraps `gs2::Machine` |
| `gui/` | the GS2 controls | after the shell |

The split with Track B: `common/cpp/gs2/` owns the bytecode loader, the
machine, `TGraalVar` objects and classes (namespace `gs2`). This program
feeds it script bytes (140, 197 and the cache) and registers its native
commands. Nothing here re-implements the machine.

## Builds

| Build | Token | Row | Folder |
|---|---|---|---|
| 6.03r7 Linux | `G3D0511C` | `net/profile.cpp` | `graal-6.03r7-G3D0511C` |
| 6.01r1 Linux | `G3D0108A` | `net/profile.cpp` | `graal-6.01r1-G3D0108A` |
| 5.30r3, 5.31r4, Windows 6.00r2, 6.00r4, 6.03r7, 6.00 betas | | later (Track D3, D5) | |
| 6.11r1 Mac, 6.1.1.3 | set by the connector script | later (Track D4) | |

Linux first: those two are unpacked native binaries, so their notes are the
most complete.

## Build and test

```
make -C common/cpp/quattro test
```

C++17, zlib and bzip2. The tests use loopback sockets only; no public
server is contacted. `quattro-session --list` prints the rows.

```
LAB_PW=... common/cpp/quattro/build/quattro-session --build 6.03r7 \
    --connect 127.0.0.1:14900 --account NAME --password-env LAB_PW
```

## Rebuild choices (not the original's)

- Receive limits: 16 MiB per frame and 4 MiB of unfinished message. The
  original's were not read.
- The machine fields of the login line are sent as `""`; the original
  sends hashes of the machine.
- The PLI 50 size counts the id byte, the body and the newline; the note
  gives the cap, not what is counted.
