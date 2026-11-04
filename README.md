# graal-delphi

Faithful rebuilds of the classic Graal Online clients, one per build, in the
language they were written in: Delphi (Object Pascal). Each rebuild aims to
behave like the original on the wire and on screen, and then gets hardened
so it can run in large test runs.

The findings these rebuilds are based on live in
[graal_analysis](https://github.com/squirelworks/graal_analysis). The
servers they are tested against are the Seihai stack, mainly
[seihai-gserver](https://github.com/squirelworks/seihai-gserver).

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad"). "Graal",
> "Graal Online" and related names are trademarks of their respective
> owners and are used here only to identify the software being
> reimplemented.

This repo holds no original Graal code, graphics, sounds or level data. The
code is written from notes on the wire protocol, file formats and observed
behaviour (in graal_analysis), not copied or translated from the original
programs. Game assets such as `pics1.png`, `arrays.dat`, ganis, heads and
bodies are loaded at run time from an install you supply. Tests that need
original data, such as the tutorial levels inside the 2.05 exe, read it
from a local path and are skipped when it is missing.

## Layout

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
graal-2.05r2-GNW03081/      Graal 2.05 rev 2
  src/                      the client (Graal205.dpr and its units)
  tests/                    Test205.dpr
graal-2.17.1-GNW22122/      Graal 2.17.1
  src/                      the client (Graal217.dpr and its units)
  tests/                    Test217.dpr
graal-2.22-GNW03014/        Graal 2.22
  src/                      the client (Graal222.dpr and its units)
  tests/                    Test222.dpr
scripts/
  build.sh                  build every rebuild and its tests
  test.sh                   run every test program
  builtin/                  draws the built-in assets and writes GBuiltin.pas / GFont.pas
  assets/merge_assets.py    merges per-version sets of original files into one graal-assets/
  loopback.sh               log a rebuild into seihai-gserver (acceptance check)
```

### Folder naming rule

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

### What goes in `common/`

A unit moves to `common/` only when it is byte-for-byte the same behaviour
in every build that uses it (the G types, zlib, the GR-V board code). Anything
a build changed, even slightly (packet ids, prop encodings, the cipher, the
login line), stays in that build's folder. When a later build differs from a
common unit, it gets its own copy in its folder rather than a flag in
`common/`.

## Toolchain

- **Free Pascal 3.2** in Delphi mode (`-Mdelphi`) is the build used here and
  in CI, on Linux, Windows and macOS.
- **Delphi**: the units avoid anything newer than Delphi 5 (no generics, no
  inline variables, `string` used as a byte buffer as in 2001-era code), and
  take the Delphi path under `{$IFNDEF FPC}` (WinSock, the Borland `ZLib`
  unit). 2.05 itself was built with Delphi 4 or 5 and DelphiX. A Delphi 5
  or 7 build has not been tried yet; it is the next toolchain check.
- DelphiX (DirectDraw) does not build outside Windows or under Free Pascal,
  so the rebuilds draw into a software surface (`GSurface`) and a front end
  shows it: a window (`--window`), or a `.bmp` (`--dump`). The window is
  X11 on Linux and GDI on Windows; macOS has none yet, so there the client
  runs headless or with `--dump`.

## Build, test, run

```
# Linux
sudo apt-get install fp-compiler fp-units-base fp-units-fcl libx11-dev
scripts/build.sh
scripts/test.sh

# Windows: install Free Pascal (e.g. `choco install freepascal`), put its
# bin\i386-win32 folder on PATH, then run the same scripts from Git Bash.
# build.sh hands the compiler native paths through cygpath.

# macOS
brew install fpc
scripts/build.sh
scripts/test.sh

# offline: walk around a level in a window, with assets from your own install
build/graal-2.05r2-GNW03081/Graal205 --level some.graal --data path/to/graal --window

# online: log into a server (password from an environment variable)
GRAAL_PW=... build/graal-2.05r2-GNW03081/Graal205 --server 127.0.0.1:14802 --account test1 --dump frame.bmp

# acceptance: log into seihai-gserver on loopback
scripts/loopback.sh path/to/seihai-gserver/target/release/seihai-gserver
```

## Roadmap for each build

Every build goes through the same phases. Phases 4 and 5 are the finishing
steps and are required before a build counts as done.

1. **Wire.** Framing, cipher, login line, the receive dispatcher. Checked
   against real captures of the original client.
2. **World.** Level loading (files and server packets), the frame loop,
   drawing the board, the player, other players, NPCs.
3. **Play.** Movement and collision, items, weapons, the build's GS1 script
   engine, editors where the build had them. Checked side by side with the
   original under Wine.
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

## Status

| Build | Token | Wire | World | Play | Harden | Release |
|---|---|---|---|---|---|---|
| [2.05 rev 2](graal-2.05r2-GNW03081/) | `GNW03081` | done | board, player from ganis, window | walking and collision; props out; other players; level links | headless stress mode, fuzzed receive path, leak checks | v0.0.1 draft |
| [2.17.1](graal-2.17.1-GNW22122/) | `GNW22122` | login with tamper check; all 79 server ids accepted | board, players and NPCs from ganis (ATTACHSPRITE, #P1 to #P30), addtiledef sheets, window | everything 2.05 plays (items, combat, NPCs and GS1, baddies, sound, maps, editor); GANI and direction props out; replaceani | from 2.05: headless stress mode, fuzzed receive path, leak checks | not yet |
| [2.22](graal-2.22-GNW03014/) | `GNW03014` | done (gen 5, bzip2); start screen and 2.22 listserver step | board, level cache, gmaps | walking and collision; props out; other players; level links; gmap edges; Training on the offline tutorial | headless stress mode, fuzzed receive path, leak checks | v0.0.1 after merge |

## Licence

Not chosen yet.

## Every build is a GUI program

Each build opens a window with the start screen when started with no
arguments, as the original clients did: Training for the offline levels,
Start for the server list from the listserver, then account and password.
Flags still run it from the command line (stress runs, CI). Each build
carries the small original assets in `common/builtin/`, so it runs with
nothing next to it; files from a real install next to the program, or
under `--data`, replace them.

A build plugs into `common/GStartScreen.pas` with:

- a `TListFetch` subclass for its listserver step (2.05: plain zlib, id 0
  `newmain`);
- a `TStartInfo`: the title lines, the background images to look for next
  to the program, and a callback that draws the character;
- its own front end, which picks the Training level and runs the game
  (see `RunGui` in `graal-2.05r2-GNW03081/src/Graal205.dpr`).

## One assets folder for every build

The original Graal files never go in this repository. A player keeps one
folder of them, `graal-assets/`, for all the rebuilt clients:

```
graal-assets/
  common/     files the same in every version that has them
  2.05r2/     one folder per version, named by the build's version label
  2.22/
```

A build looks for a file in its own folder (or `--data`), then in
`graal-assets/<version>/`, then in `graal-assets/common/`, and else uses
its built-in assets (`common/GAssetDirs.pas`). `graal-assets` is found next
to the program or one folder up, so several clients can share one copy.
`scripts/assets/merge_assets.py` builds the folder from per-version sets.

A version that shipped with another version's files reads that version's
folder next. Graal 2.17.1 came in the same folder as 2.22, so the 2.17.1
build looks in `graal-assets/2.17.1/` (if there is one), then
`graal-assets/2.22/`, then `common/`. No second copy is needed.
