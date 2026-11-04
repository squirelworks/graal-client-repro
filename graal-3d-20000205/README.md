# Graal3D, February 2000 (`graal-3d-20000205`)

A rebuild of **Graal3D**, the 3D side project of February 2000, in Delphi
(Object Pascal) like the original. Graal3D is its own program: a Delphi
client (`Graal3D.exe`, DelphiX in Direct3D Retained Mode) and its own
server (`GServer.exe`, TCP 14901). It does not talk to the 2D GServer or
the list server, has no tiles, ganis or NPC scripts, and its levels and
player are DirectX `.x` meshes.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad"). "Graal"
> and related names are trademarks of their respective owners and are used
> here only to identify the software being reimplemented.

This folder holds no original Graal3D code, meshes, textures or levels. The
code is written from the notes in graal_analysis, not copied or translated
from the original program.

## Folder name

Graal3D sends `GR3DV002` where the 2D clients send their version token, but
that string names the protocol, not a build. Under the rule for builds
without a token the folder carries the build date instead: both programs in
the archive carry resource stamps of 2000-02-05.

## Sources

| What | Where |
|---|---|
| The archive | `graal3d.7z`: `Graal3D.exe` (MD5 `305c985a020cec6ab8d81ac95d447343`), `GServer.exe`, `graal3dconfig.txt`, `level1.x`, `startlevel.x`, 8 player meshes, 12 BMPs |
| Same program on Drive | `# Graal3D #` folders: `Graal3D.zip` (913,556 bytes) and `Graal3D.rar` (580,632 bytes), each in two copies; `New Graal 3D Beta Version.rar` (1,998,422 bytes) was not opened for this build |
| Wire, files, behaviour | graal_analysis `graal3d/`: `protocol.md`, `formats.md`, `client-behaviour.md`, `collision.md`, `camera.md`, `lab-2026-10-30.md` |
| Test server | graal_analysis `graal3d/reference-server/g3dserver.py`, written from the notes; the real client logs into it |

The 4.x `Graal3DEngine.dll` (Torque, 2006) is a different program and is
not part of this folder.

## Units

| Unit | What it does |
|---|---|
| `src/Graal3D.dpr` | the program: start window, command line, the 50 ms frame loop |
| `src/Codec3D.pas` | frames (u16 length + zlib, no key byte), packet ids, `GR3DV002` login line, the prop table (3D positions, 1-byte angle, 24-bit colours in four 6-bit groups, the IPv4 prop) |
| `src/Client3D.pas` | TCP link and what each server message does; the per-tick props diff; UDP position and chat with the other players |
| `src/Udp3D.pas` | the client-to-client UDP socket |
| `src/XFile3D.pas` | DirectX text `.x` reader: meshes, polygons, material lists and references, texture names and coordinates, frames |
| `src/Render3D.pas` | a software renderer standing in for Direct3D RM: z-buffer, perspective-correct wrapped textures, the library's field 0.5 viewport |
| `src/World3D.pas` | walking, running, jumping, the probe collision, the follow camera, other players, the chat log |
| `src/Config3D.pas` | `graal3dconfig.txt` |
| `src/Connect3D.pas` | the start window and the chat line |
| `src/Window3D.pas` | the window with Graal3D's keypad keys (X11 / GDI) |
| `src/Builtin3D.pas` | this build's own stand-in level and player, used when the player's files are not there |
| `src/Run3D.pas` | clock, stop signals, key scripts, JSON for scripted runs |
| `tests/Test3D.dpr` | the test suite |
| `loopback3d.sh` | logs two copies into the reference server |

The common units used are `GTypes`, `GZlib`, `GSocket`, `GSurface`,
`GFont`, `GAssetDirs` and `GStartScreen` (for its Windows console helper).
`common/GWindow.pas` does not read the keypad, so this build has its own
window unit.

## What works (0.0.1)

- **Start window.** The original's fields in its order and with its
  labels: Nickname (empty), Server IP, Port `14901`, Account and Password
  (`guest` / `guest`), and Start, with `logo.bmp` on top when it is there.
  Offline (walks `level1.x` with no server) and Quit are this build's.
  Compared by eye with the real `Graal3D.exe` under Wine: same fields and
  defaults; the original is a small wood-panel dialog with a drop-down for
  the server, this build draws its own plain window at 640×480.
- **Login.** `GR3DV002`, account and password; the login line and the first
  props line (the full look and the UDP port) go out in one frame, as the
  original does.
- **Server messages.** Own props (3), other players (2, created on first
  sight, prop 50 in or out of the level, prop 51 gone), level name (1) and
  level text (0, saved under its name next to the program, or "you already
  have it"), leader (4), disconnect text (5), session (6), administrator
  message box (8), raw data (100, dropped).
- **UDP.** One socket (random port, or `fixedudpport` when `fixedport` is
  on, none with `noudp`); 9-byte position datagrams to the players in the
  level when props 1–5 change, chat datagrams on Enter; datagrams accepted
  only from a known player's address and port.
- **The world.** Levels and the eight player meshes from `.x` files,
  textures from BMPs; body and head mesh and texture from props 6–9, arm,
  hand and shoe colours from props 10, 17 and 11.
- **Moving.** Keypad 8/2 forward and back along the camera's view, 4/6
  step sideways, 5 jump, 0 camera follow on/off. 8 units a tick, ×1.5 after
  25 ticks; back alone walks backwards along the facing; the jump table
  (47 up, letting go early cuts it); the ±4000 world edge; body bob.
- **Collision** from the probe set in the notes: four feet probes, three
  upper probes 35 up, step height 30, the wall slide rule (clear at 3,
  started inside at −5).
- **Camera.** About 220 behind and 80 above, the quadratic follow, pitch
  0.15 rad, the library's field 0.5 (640 pixels per unit at distance 1 on
  the 640×456 view).
- **Chat.** Enter opens the chat line, Enter sends it; the log at the bottom
  left, "nickname: text", 10 seconds a line; lines over 200 end in `...`.
- **Config.** `graal3dconfig.txt` next to the program is read, and written
  back when the start window connects.
- Linux (X11) and Windows (GDI, 32-bit) windows; on macOS it runs headless
  or with `--dump`.

## Where to put your Graal3D files

The program finds its files from its own folder and nothing above it:

```
Graal3D/
  Graal3D(.exe)
  graal-assets/            (from graal-assets.zip)
    3d/                    the Graal3D files
    common/
```

A file is looked for next to the program first, then in
`graal-assets/3d/`, then in `graal-assets/common/`. Copying the contents of
the Graal3D archive next to the program works too. `--data DIR` points at
another folder. With no files the build's own stand-in level and player are
used.

What this build opens, by name (all from `graal3d.7z`):

| File | Used for |
|---|---|
| `level1.x` | the client's default level (Offline) |
| `body.x`, `head.x`, `armleft.x`, `armright.x`, `handleft.x`, `handright.x`, `footleft.x`, `footright.x` | the player |
| `body.bmp`, `man.bmp` | body and head textures (`body1.bmp` is the other body a player can pick) |
| `grass.bmp`, `way.bmp`, `stones.bmp`, `wall.bmp`, `tower.bmp`, `platform.bmp`, `clouds.bmp` | the textures `level1.x` and `startlevel.x` name |
| `logo.bmp` | the start window picture |
| `graal3dconfig.txt` | settings (optional; it is written next to the program) |

`startlevel.x` is a server file: the server sends it, and the client saves
it next to itself.

## Running it

```
Graal3D                                                     # start window
GRAAL_PW=guest Graal3D --server HOST[:14901] --account guest --nick Stefan --window
Graal3D --offline --window                                  # level1.x, or the stand-in
Graal3D --level some.x --window
Graal3D --offline --frames 80 --keys "fwd*40,jump*8,say:hi" --dump frame.bmp
```

Arrow keys walk as well as the keypad (they are what the keypad sends with
Num Lock off). Esc leaves the game.

## Choices this build made

The notes leave these open; each is marked "this build" in the code.

- Host: the start window's server field starts as `listserver.graal.in`
  (Graal3D is from before the server list; never a loopback address). The
  original's own default was the loopback address, and its shipped config
  named a server that is gone.
- The far clipping plane is 5000 (the original was not read for it).
- Light: one ambient and one directional part, flat per face; faces are
  drawn from both sides.
- Where the eight player meshes sit on the body (the files carry no frame
  layout): head at +29, arms and hands at +27, feet at ±5, +8.
- The feet probes test walls a step above the feet, so a step up to 30 is
  climbed; a floor more than 30 above the feet but below the head blocks.
- Walls: the probe pushed onto the wall's plane must fall inside the face.
- Walking off an edge falls by the jump table's way down.
- The animation counter runs 0–39 while walking; the jump sets 40.
- The chat line has to be opened with Enter, so the keypad digits walk
  instead of typing.

## Not yet (0.0.2 and on)

- "Hardware options" (F1) and "Player look" (F2) windows; Ctrl+Enter full
  screen. Their settings are read from `graal3dconfig.txt` meanwhile.
- The registry store of nickname, account and the DES-hidden password.
- Arm and leg swing while walking (only the body bob is drawn).
- The "Graal execution file is corrupted" self-check.
- A side-by-side check of play against the real client. Under Wine the
  real client's start window opens, but past it the client needs
  Microsoft's `d3drm.dll` (Wine's is a stub, see the lab notes), so no
  real login could be compared here; the rebuild's login was checked
  against the reference server.
- The server drop-down list of the start window.
- Admin login (id 1) and its account and player lists: no admin client
  shipped for Graal3D.
