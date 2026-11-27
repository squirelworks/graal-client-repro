# Frankenstein 6.037

A community-requested experimental client: a **v6.037** host with **v5.120
Graal3D** folded in, and **UDP left enabled**. The Graal3D half uses
this repo's 5.12 repro, [`graal-5.12-G3D14097`](../graal-5.12-G3D14097/)
(v5.120 is 5.12), with the Mac 5.12 repro
[`graal-5.12mac-G3D15097`](../graal-5.12mac-G3D15097/) beside it. People have been calling it
a cursed mixture, and that is the right word. It is one program on purpose
made from two generations that the faithful folders keep apart.

The program is `frankenstein-6037`: the 6.03r7 Quattro program (the same
rebuild Graal603w hands its game to) with the 5.12 repro's Graal3D link
linked in. It builds on **macOS** (the Graal3D test build), **Linux** and
**Windows** from the same sources. It is version 0.0.1: hit or miss.

The other experimental mix, a v6.113 host with the same v5.120 fold-in,
lives in [`frankenstein/`](../frankenstein/). This tree does not change
that one. Releases, tags, and the workflow here are their own series.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

## Goal

| Piece | What this mix keeps | Where the behaviour notes already live |
|---|---|---|
| Host | v6.037 session, scripts, and file requests | [`graal-6.03r7win-G3D0311C`](../graal-6.03r7win-G3D0311C/) (Windows 6.03r7, token `G3D0311C`; [`docs/v6-repro.md`](../docs/v6-repro.md) says a 6.0.3.7 repro uses that token) and [`graal-6.03r7-G3D0511C`](../graal-6.03r7-G3D0511C/) (Linux 6.03r7, token `G3D0511C`, the same release). Notes: [`docs/v6-repro.md`](../docs/v6-repro.md) |
| World | v5.120 Graal3D, folded into that host | v5.120 is 5.12, written the way the 6.x builds are (6.03r7 is v6.037). The rebuilds are [`graal-5.12-G3D14097`](../graal-5.12-G3D14097/) (Windows, token `G3D14097`) and [`graal-5.12mac-G3D15097`](../graal-5.12mac-G3D15097/) (Mac OS X, token `G3D15097`, same engine source, seen on the wire in the lab). Both split the Delphi launcher from `GraalEngine.dll` and `Graal3DEngine.dll` |
| Net | UDP stays enabled, including on the game connection | [`docs/v6-repro.md`](../docs/v6-repro.md) (UDP) says a 6.x connect path does not open a datagram socket, and that whether the 6.0.3.7 game connect path calls the opener is not found. This experiment turns that path on and keeps it on |

The faithful client folders stay matched to their own real clients. Code
for this mix grows under `frankenstein-6037/` and does not change those
folders to suit the mix.

Game data (tiles, ganis, heads, bodies, levels) is loaded from the player's
own install (`--assets`), as `quattro-play` does. This folder carries none
of it.

## How it plays

| Piece | What it is | Code |
|---|---|---|
| Host | `common/cpp/quattro`'s `Shell::Program` on the 6.03r7 row: token `G3D0311C` and the `win` login tail on Windows, `G3D0511C` and `linux` on Linux and macOS (there is no Mac 6.03r7). Session, 178 warps, levels, players, GS2 weapon scripts, the 6.x HUD, 1024 x 768 | `src/host6037/` |
| 3D | A server whose list name starts with `3 ` (given with `--server-name "3 Lab"`, or reached by the Login server's 178 warp to one, as the real 5.12 entered 3D) loses the marker and is entered on two links at once, as the 5.12 engine library does: the Torque link to the listed port + 1, then the TCP login on the listed port. The link is the 5.12 repro's protocol 24 (`common/cpp/graal3dengine`): handshake, packets and acks, events, ghosts, the control object and its movement, login steps 2 to 6. Server text (weapons, flags, scripts) goes to the 6.x program's GS2 machine, and its server triggers go back over the link as `events` lines | `src/net/udp/` (glue), `src/host6037/` |
| UDP | Left enabled: the 3D link is a UDP socket on a random local port, in a 6.x host whose stock connect path opens none. The two links live and die together | `src/net/udp/` |
| Scripts | The 6.x GS2 machine runs the server's 3D weapons. In 3D it also has the 5.12's `GameObject` and `Camera` objects (`new GameObject(name)`, `player.camera`) with their typed members in the 5.12's formats, and `timevar3`. Show-images on the screen layer (layer 4 and up) are drawn over the whole 3D view. A server move of the player's own object is reported back, and 3D files are asked for by the 5.12's names (images bare, never `.cs` or `.ter`) | `src/graal3d5120/gs2_3d.*`, `src/host6037/` |
| View | Once the link reaches step 6 and the server names a Camera, the 5.12 repro's renderer (`common/cpp/graal3dengine/render`) draws the world over the frame: the sky, the shapes found in `levels3d/` (beside the program and under each `--asset-root`), the streamed terrain, water and name tags, with the lab's lighting and movement. Until the server names a Camera the view is black, as the 5.12's is. The draw distance is the player's `visibledistance3D` from a `game_config.txt` beside the program or in an asset root (1000 by default, at most 2400). The 6.x frame stays as a quarter-size inset bottom left. `--no-3d-view` keeps the plain 6.x frame | `src/graal3d5120/` |
| Renderers | The frame is drawn by OpenGL 3.2 core (`src/graal3d5120/gl/`, offscreen, read back into the frame) or by the software rasteriser, behind one interface (`renderer.hpp`), with the same rules (`draw.hpp`'s shared pieces). `--renderer auto` (the default) takes OpenGL and falls back to software. The GL library and context (EGL, CGL, WGL) are loaded at run time, so no build needs GL headers and a machine without OpenGL 3.2 still runs. A frame-rate counter sits top left (`--no-fps` hides it) and is logged | `src/graal3d5120/` |

The real Torque world (terrain, interiors, DTS and `.3ds` shapes, sky
textures) is a renderer of its own for `common/cpp/graal3dengine`, shared
with the 4.x and 5.x folders; this view gives way to it when it exists.

## Running it

```
PW=... frankenstein-6037 --connect HOST:PORT --account NAME --password-env PW --assets DIR
PW=... frankenstein-6037 --connect HOST:PORT --account NAME --password-env PW --server-name "3 Lab"
frankenstein-6037 --offline start.nw --assets DIR
```

With the default server name (`Login`) the Login server's warp decides; a
`3 ` warp takes the player into 3D. The secure login follows the player's
setting as `quattro-play` does. `--headless --seconds N --shot FILE.png`
runs without a window and saves the last frame. The program keeps the 6.x
50 ms tick as its clock; the 3D view draws between ticks on its own clock,
up to `--max-fps` (60; 0 for no cap) with OpenGL, and at most about half
the time with the software renderer, so GS2 timers and walking stay
real-time when the software renderer is slower than a tick.
`--renderer opengl|software` picks the backend (`auto` by default).
`FRANK_GL_LIBRARY` names a GL library to load instead of the system's,
such as Mesa's `opengl32.dll` on a Windows VM with no GPU driver. The 3D
server must take protocol 24 on its port + 1, as the Seihai gserver's
`graal3d` mode does.

```
frankenstein-6037 --bench all --seconds 5             # frame rates on the conformance worlds
frankenstein-6037 --bench grass --compare --shot-dir out/   # against the software renderer, with PNGs
```

## Build and test

```
make -C frankenstein-6037          # build/frankenstein-6037 (.exe on Windows)
make -C frankenstein-6037 test     # the view, and the loopback run below
frankenstein-6037/test.sh          # both, then stages build/frankenstein-6037/ with MANIFEST.txt
```

The same tools as `common/cpp/quattro`: a C++17 compiler, zlib and bzip2,
Xlib on Linux (headless without it), Cocoa on macOS, MSYS2 UCRT64 on
Windows. The loopback test starts its own servers: a Login server that
takes the 6.03r7 login and sends 178 to `3 Lab`, a game server on a port
whose next port is a UDP server answering the handshake and replaying the
recorded protocol-24 session (`common/cpp/graal3dengine/tests/vectors.hpp`).
It checks both logins carry the 6.03r7 token, the link reaches step 6 with
the player's object, the view draws it, and closing sends the 3D
disconnect.

The manifest records the mix and three placeholders: `<server>`, `<port>`,
`<md5>`. Those stay placeholders until a real check has a value to put
there.

## Releases stay on their own track

Frankenstein 6.037 is cut on its own. The combined client release
([`.github/workflows/release-all.yml`](../.github/workflows/release-all.yml),
tag `vX.Y.Z`, one version for every faithful client) does not build this
folder, does not call this workflow, and does not attach these zips.
`release-all.yml` only accepts `graal-*`, `javagraal-2000`,
`zelda-online1-Z3V102`, `zelda-online2-Z3V103`, and `graalgb-1.10`.
`frankenstein-6037` is outside that list. It is also outside the
[`frankenstein`](../frankenstein/) release (`frankenstein-vX.Y.Z`).

The separate pipeline is
[`.github/workflows/frankenstein-6037.yml`](../.github/workflows/frankenstein-6037.yml).

- **When it runs.** Pull requests and pushes to `main` that touch
  `frankenstein-6037/**`, the shared code it compiles
  (`common/cpp/quattro`, `common/cpp/graal3dengine/src`, the GS2 machine,
  `common/torque/gui`) or that workflow file, and a manual run from the
  Actions tab. A change under `frankenstein/` does not start it.
- **What it builds.** `frankenstein-6037` on macOS, Linux, and Windows,
  with `test.sh` (the loopback run) on each.
- **How a release is cut.** Actions → **frankenstein-6037** → Run
  workflow, on `main`. Set version to a three-part tag such as `v0.0.1`
  (empty means build only). Publish defaults to a draft. The release tag
  is `frankenstein-6037-v0.0.1` (prefix `frankenstein-6037-v`, then the
  three-part version). The draft carries three zips:
  `frankenstein-6037-v0.0.1-macos.zip`,
  `frankenstein-6037-v0.0.1-linux.zip`,
  `frankenstein-6037-v0.0.1-windows.zip`. Squirrel publishes the draft.
- **Version file.** [`VERSION`](VERSION) is `0.0.1`.
  These versions are not the combined `v0.0.5` line, and they are not the
  `frankenstein/` line. Notes for a release go in
  [`RELEASE_NOTES.md`](RELEASE_NOTES.md).

Editing `.github/workflows/frankenstein-6037.yml` also selects every
Pascal client in the main `ci` workflow. That selector
(`scripts/ci/select_pascal_builds.py`) treats every file under
`.github/workflows/` as shared CI. This folder does not change that
rule. A change that stays inside `frankenstein-6037/` does not select
those clients.

## Layout

```
frankenstein-6037/
  README.md            this file
  RELEASE_NOTES.md     notes for frankenstein-6037-v* drafts
  VERSION              version (0.0.1)
  Makefile             the program and its test
  build.sh             make, then stage build/frankenstein-6037/ with MANIFEST.txt
  test.sh              make test, build.sh, check the manifest
  src/
    main.cpp           arguments, window, the 50 ms loop
    host6037/          the 6.03r7 program and the `3 ` path (host.*)
    bench.*            --bench: the conformance worlds drawn offline for frame rates
    graal3d5120/       the 3D view (view3d.*), its backends (renderer.*) and OpenGL (gl/)
    net/udp/           the 5.12 link on a UDP socket (link3d.*)
    platform/          notes per platform (windows come from common/cpp/quattro/draw)
  tests/               frankenstein_test.cpp (loopback)
  res/                 embedded resources (empty of game data)
```

## Not yet

- [x] v6.037 host under `src/host6037/`: the 6.03r7 Quattro program,
      Windows `G3D0311C` and Linux `G3D0511C` rows.
- [x] v5.120 Graal3D under `src/graal3d5120/` and `src/net/udp/`, inside
      that host: the 5.12 repro's protocol-24 link, entered by a `3 `
      server or a 178 warp to one.
- [x] UDP enabled on the game connection (`src/net/udp/`).
- [x] macOS, Linux and Windows builds of the same client in
      `frankenstein-6037.yml`.
- [x] Loopback coverage against servers the run starts.
- [x] The Torque world drawn (terrain, interiors, DTS and `.3ds` shapes,
      sky) by the renderer in `common/cpp/graal3dengine`, shared with the
      4.x and 5.x folders, while the server names a Camera.
- [ ] Mouse-look, and keys of the 5.12's own 3D controls (the arrows walk
      the 6.x player, and the 3D object takes its steps; keyboard input
      with a movetype was not run on the real 5.12).
- [ ] `TerrainChunkEvent`, and the `fixedudpport` option (14899).
- [ ] The 6.x start screen and server list: the program starts straight
      into its session, as `quattro-play` does.
- [x] A lab run against the Seihai gserver's `graal3d` mode
      ([`docs/lab/frankenstein-6037-lab-2026-11-26.md`](../docs/lab/frankenstein-6037-lab-2026-11-26.md)):
      login, the 178 warp, the UDP link to step 6, ghosts, server moves
      and the 6.x inset work; the server must offer 6.03r7-token logins to
      its UDP side (seihai-gserver, same day).
- [x] The own 3D object following the arrow keys (the 6.x walk), and a
      script setting `player.position`; the server receives both.
- [x] An OpenGL 3.2 core renderer with the software one as fallback, a
      frame-rate counter, and the 3D view off the 50 ms tick.
- [x] The 5.12 GS2 3D objects a weapon3d uses most: `GameObject` (made
      by `new`) and `player.camera`, with the `GameObject`/`SceneObject`
      members of the typed table in the 5.12's formats
      (`src/graal3d5120/gs2_3d.*`, conformance C026, C030), and `timevar3`.
- [ ] The rest of the 5.12 GS2 3D surface: `castRay`, `get3Dobjects`,
      `getz`, the `Sky` and `Sun` setters, mounts, `ActionMap`, the
      editor classes (Graal_analysis
      `torque/gs2-3d-typed-surface-512-2026-11-26.md`).
- [x] GS2 show-images on the screen layer over the whole 3D view (C010).
- [x] The `seihai3d` v1 hello and reply, with `chat_3d` (chat lines in
      the 3D view) and `frame_stats`; a server without the extension gets
      a plain 5.12 (`--no-seihai3d` sends no hello).
- [ ] The other `seihai3d` v1 bits (`world_terrain_cache`,
      `chunk_relight`, `view_distance`, `fast_pacing`, `wide_ghosts`,
      `world_chunks`), and chat bubbles over players.
- [ ] A Metal backend (OpenGL still runs on current macOS, on Metal).
- [x] The files step 6 needs: shapes and textures the renderer cannot
      find are asked for by name and kept in `<assets>/levels3d/` with
      what the server pushes (terrain).

## Rules for this folder

- Placeholders only for endpoints and digests: `<server>`, `<port>`,
  `<md5>`. The community list-server hostname, when a later client needs
  one, is `listserver.graal.in`, the name the 6.03 folders already use.
- Behaviour comes from the notes named above. No code addresses, no
  decompiler symbol names, and no decompiled C in this tree, in commits,
  or in pull requests.
- The engine is the Quattro program the 6.03 folders use, with v5.120
  Graal3D folded into that host. No modern Torque3D base. A small
  MIT-licensed piece from modern Torque3D is allowed only where that older
  Torque needs it (the string Huffman table kept under
  `common/cpp/third_party/torque3d/`, which the link uses).
- Original game files stay in the player's install, not in git.
