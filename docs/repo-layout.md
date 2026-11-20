# Repository layout

How this repository is organised, how build folders are named and what may be
shared between builds. The [README](../README.md) has the overview.

## Folders

```
common/                     code that is the same across builds
  GTypes.pas                GCHAR / GSHORT / GINT3..5 / GSTRING, message reader
  GZlib.pas                 zlib in and out of string buffers
  GBzip2.pas                bzip2 in and out of string buffers (gen 5, 2.22 on)
  GSocket.pas               non-blocking TCP, polled from the game tick
  GLevel.pas                64x64 level: GR-V1.0x, Z3-V1.0x, GLEVNW01, board packet, GR-V writer
  GSurface.pas              32-bit software surface, tile sheet blit, BMP/PNG/GIF/JPEG loading, palette recolour
  GArrays.pas               arrays.dat tile types (what blocks)
  GAni.pas                  GANI0001 animations
  GWindow.pas               a window, keyboard, mouse and typed text (X11 / Win32 GDI)
  GFont.pas                 an original 5x7 font for the window
  GStartScreen.pas          the start screen and server list every build opens with
  GGs1.pas                  the GS1 script language (shared interpreter)
  GBuiltin.pas              built-in original assets, compiled in (generated)
  GAssetDirs.pas            where a build finds the player's own Graal files (graal-assets/)
  builtin/                  those assets as files (scripts/builtin/make_builtin.py)
  win/                      the Windows manifest every client compiles in
graal-<version>-<token>/    one folder per build (76, from graal-b1-19980906 to
                            graal-worlds-7.0.1.7.5.0-20260403); four shown here
javagraal-2000/, zelda-online1-Z3V102/, zelda-online2-Z3V103/   the Java clients
graalgb-1.10/               the Game Boy Color demo
graal-2.05-GNW03081/        Graal 2.05
  src/                      the client (Graal205.dpr and its units)
  tests/                    Test205.dpr
graal-2.05r2-GNW03081/      Graal 2.05 rev 2
  src/                      the client (Graal205.dpr and its units)
  tests/                    Test205.dpr
graal-2.17.1-GNW22122/      Graal 2.17.1
  src/                      the client (Graal217.dpr and its units)
  tests/                    Test217.dpr
graal-2.22-GNW03014/        Graal 2.22
  src/                      the client (Graal222.dpr and its units)
  tests/                    Test222.dpr
HANDOFF-CURSOR.md           state, rules, on-hold work and open decisions
AGENTS.md                   binding rules for agents (and .cursor/rules/)
ROADMAP.md                  the project checklist
scripts/
  build.sh                  build every rebuild and its tests
  test.sh                   run every test program
  builtin/                  draws the built-in assets and writes GBuiltin.pas / GFont.pas
  assets/merge_assets.py    merges per-version sets of original files into one graal-assets/
  assets/needed_assets.py   cuts it to the files the clients open and zips it (docs/assets.md)
  loopback.sh               log a rebuild into seihai-gserver (acceptance check)
  win/make_winres.py        gives each client its src/<Program>.rc (version info, manifest)
```

## Folder naming rule

Each build gets one folder named

```
graal-<version>-<token>
```

- `<version>` is the build as players knew it, lower case, no spaces:
  `2.05r2` for "2.05 rev 2", `2.17.1`, `2.22`, `2.31`.
- `<token>` is the 8-character version token that build sends in its login
  line, exactly as on the wire (`GNW03081` for 2.05 rev 2). It is the id the
  server sees, so it is the id the folder carries. The token comes from the
  binary or a capture, never from memory; graal_analysis
  `client-internals/version-tokens.md` lists the known ones.

Several builds can share a token (2.05, 2.05 rev 1 and 2.05 rev 2 all send
`GNW03081`). The version part keeps their folders apart.

## What goes in `common/`

A unit moves to `common/` only when it is byte-for-byte the same behaviour
in every build that uses it (the G types, zlib, the GR-V board code). Anything
a build changed, even slightly (packet ids, prop encodings, the cipher, the
login line), stays in that build's folder. When a later build differs from a
common unit, it gets its own copy in its folder rather than a flag in
`common/`.

The GS1 language (`GGs1.pas`) is shared under that rule: it holds only the
language (parsing, statements, expressions, the command table), and what
each command does lives in the build's own NPC host (`Npc205`, `Npc217`,
...). A build uses it until it is found to read GS1 differently; then it
takes its own copy, as for any other unit. The NPC, baddy, sound, map and
editor units stay per build.

## The shared start screen

A build plugs into `common/GStartScreen.pas` with:

- a `TListFetch` subclass for its listserver step (2.05: plain zlib, id 0
  `newmain`);
- a `TStartInfo`: the title lines, the background images to look for next
  to the program, and a callback that draws the character;
- its own front end, which picks the Training level and runs the game
  (see `RunGui` in `graal-2.05r2-GNW03081/src/Graal205.dpr`).

## The phases of each build

Every build goes through the same phases. Phases 4 and 5 are the finishing
steps and are required before a build counts as done.

1. **Wire.** Framing, cipher, login line, the receive dispatcher. Checked
   against real captures of the original client.
2. **World.** Level loading (files and server packets), the frame loop,
   drawing the board, the player, other players, NPCs.
3. **Play.** Movement and collision, items, weapons, the build's GS1 script
   engine, editors where the build had them. Checked side by side with the
   original under Wine, for behaviour rather than looks
   ([functional-parity.md](functional-parity.md)).
4. **Harden and stress.** A headless mode that runs the same code with no
   drawing, so one host can run many instances; profiling and optimisation
   of the tick; no leaks over long runs; survives disconnects, slow links
   and malformed or hostile packets without crashing; fuzzed receive path.
   The build then joins the Seihai 1000-player stress runs as one of the
   client mixes.
5. **Release.** Once phase 4 is merged, the build gets its own GitHub
   release, versioned so it can be recompiled and released again as more
   is learned about it. The tag is the folder name and the version
   (`graal-2.05r2-GNW03081-v0.0.1`). The release text is the folder's
   `RELEASE_NOTES.md`, and it carries the built Linux, Windows and macOS
   binaries. `.github/workflows/release.yml` (run from the Actions tab with
   the folder name and version, or by pushing the tag) builds that one
   folder and makes a draft release; Squirrel reviews it and presses
   Publish.
