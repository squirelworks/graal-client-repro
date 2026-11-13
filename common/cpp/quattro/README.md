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
| `tools/` | (none) | `quattro-session` logs a session; `quattro-play` runs the program in a window or headless (`--shot` writes the last frame as PNG) |
| `files/` | levels and packages | **done**: `GR-V1.00`–`1.05` (1.05 board layers), the 101 board packet, links, chests, signs; `GANI0001` sprite-mode ganis (sprites, steps, WAIT, SINGLEDIRECTION, ATTACHSPRITE/2, defaults). Packages and movie-mode ganis next |
| `draw/` | the draw passes and the window | **done**: the world passes in the original's order on a software canvas (shared with `common/torque/gui`), the lobby rule, an Xlib window and a headless window; players drawn from their gani with head, body, sword, shield and hats from the player's folder (`draw/assets`), the body in the player's five colours; the 6.x HUD (`draw/hud`: tabs, sword and glove, AP and MP bars, counters, hearts) |
| `shell/` | the program loop, `StartScript_*`, `GuiGraalCtrl` | **started**: the 50 ms loop, level name/board/links/chests from the session, window title per server, and the script host on `gs2::Machine` (140, 197 with the `GRESCR01` cache, 33/34, 190), and the GUI host: `StartScript_*` read from the player's own program file (`--program`), `MainMenuGui2D` as the content, the world drawn in its `GuiGraalCtrl`, mouse and keys from the window. The show-image emitters run each tick and draw through the painter (add, transparent, subtract, day-night). Next: the engine actions and `GuiShowImgCtrl` animations |
| `world/` | `TServerPlayer` and the props | **done**: the prop stream of 9 and 8 (the 2.22 table plus X2/Y2/Z2), the initial props after login, and the X2/Y2 movement diff each tick; walking against `arrays.dat` walls and chests with the six-point box, the corner nudge, and `push` with 38 `pushed,0` |
| `gui/` | the GS2 controls | in `common/cpp/gs2` (`gui.hpp`, B4): one control tree for 4.x to 6.x; Quattro paints it on its canvas (`shell/gui_host`) |

The split with Track B: `common/cpp/gs2/` owns the bytecode loader, the
machine, `TGraalVar` objects and classes (namespace `gs2`). This program
feeds it script bytes (140, 197 and the cache) and registers its native
commands. Nothing here re-implements the machine.

## Builds

| Build | Token | Row | Folder |
|---|---|---|---|
| 6.03r7 Linux | `G3D0511C` | `net/profile.cpp` | `graal-6.03r7-G3D0511C` |
| 6.01r1 Linux | `G3D0108A` | `net/profile.cpp` | `graal-6.01r1-G3D0108A` |
| 4.04r2 Windows (the engine library's session) | `G3D17026` | `net/profile.cpp` | `graal-4.04r2-G3D17026` |
| 5.00r7 Windows (the engine library's session) | `G3D22067` | `net/profile.cpp` | `graal-5.00r7-G3D22067` |
| 5.12 Windows (the engine library's session) | `G3D14097` | `net/profile.cpp` | `graal-5.12-G3D14097` |
| 5.30r3, 5.31r4, Windows 6.00r2, 6.00r4, 6.03r7, 6.00 betas | | later (Track D3, D5) | |
| 6.11r1 Mac, 6.1.1.3 | set by the connector script | later (Track D4) | |

Linux first: those two are unpacked native binaries, so their notes are the
most complete.

The 4.x and 5.0 rows are used by `common/cpp/graalengine`, whose session
is this program's. 5.12 carries two codec rules of its own, set from its
row: a fifth login field (the quoted Windows version), and compressed
frames that are always zlib below the bzip2 size and stepped `len / 4`
rounded down (`Cipher::set_packed_round_down`; Graal_analysis
`protocol/v5v6-lab-play.md`, "5.12's cipher step count").

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

## Window size

The 6.03r7 row opens 1024 x 768, the size the real Linux client starts at
(HUD lab, 2026-11-12); other rows open 640 x 480, as Seihai's Issho does.
`quattro-play --size WxH` changes it. As in the real client, a bigger
window shows more of the level and nothing scales: tiles stay 16 pixels,
the HUD's left part keeps its x from the left edge and the hearts theirs
from the right. The HUD draws from the player's own `state.png` (and
`sprites.png` and `swordN.png`); with no `state.png` there is no HUD.
The Windows 6.x window and frame were not measured.

## Rebuild choices (not the original's)

- Stand-ins until the real art is drawn: tiles with no `pics1.png` are flat
  colours from their id; chests are boxes, and so is a player when no
  gani (not even `idle`) is in `--assets`. Body colours take the
  palette entries and the 20 colours of the Pascal clients; that 6.x uses
  the same entries was not seen in a lab. `PARAMn` sprites (the carried object) are
  not drawn yet. A gani steps once per 50 ms tick and starts over when the
  player's gani changes.
- Upper board layers treat tile 0 as empty; each layer's bit stream starts
  on a new byte. The 5.x note gives the layer count and boards, not these.
- Walls come from `arrays.dat` in `--assets` (array 0 passable, array 1 liquids). With no `arrays.dat` every tile is passable; where 6.x reads its own table was not seen in the lab. The 0.0625 snap after a step is left out.
- GUI text uses the built-in Liberation Sans 16 px faces (the same tables as `common/GUiFont.pas`) in place of the player's TrueType faces; GUI bitmaps are read as PNG from `--assets` and its `gui`, `images` and `levels` folders. The playfield follows the player over the whole window and is clipped to the `GuiGraalCtrl`.
- The initial props send nickname "unknown", as the lab's 6.03r7 did with no nickname set.
- Offline (`Program::start_offline`, the engine library's offline mode): a
  level or a gmap from `--assets`; a gmap's parts join at their edges as one
  board in global tiles (the 2.22 lab crossing), and a part's name is
  looked for in the gmap's folder first, then anywhere under `levels`. With
  no GS1 engine, the level NPCs' `addtiledef`, `setplayerprop`,
  `replaceani` and `setani` lines are read wherever they stand, not run.
- Gmaps (`files/gmap`): the `LEVELNAMES` grid, or the DungeonGenerator's
  short form rebuilt from `GENERATED` (Graal_analysis
  manual/03-formats/02-gmap.md); the heights and images are not read.
- The tile sheet is `pics1.png` in `--assets`, `levels` or `levels/tiles`
  (where the 4.x installs keep it).

- Receive limits: 16 MiB per frame and 4 MiB of unfinished message. The
  original's were not read.
- The machine fields of the login line are sent as `""`; the original
  sends hashes of the machine.
- The PLI 50 size counts the id byte, the body and the newline; the note
  gives the cap, not what is counted.
