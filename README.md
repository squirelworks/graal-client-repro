# graal-delphi

Faithful rebuilds of the classic Graal Online clients, one per build, in the
language they were written in: Delphi (Object Pascal). Each rebuild aims to
behave like the original on the wire and on screen, and then gets hardened
so it can run in large test runs.

The findings these rebuilds are based on live in
[graal_analysis](https://github.com/squirelworks/graal_analysis). The
servers they are tested against are the Seihai stack, mainly
[seihai-gserver](https://github.com/squirelworks/seihai-gserver).

**Working on this repo?** Start with [HANDOFF-CURSOR.md](HANDOFF-CURSOR.md)
(state, rules, what is on hold), [AGENTS.md](AGENTS.md) (binding rules) and
[ROADMAP.md](ROADMAP.md) (what is next, as checklists). Every client's
latest release is in [RELEASES.md](RELEASES.md).

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
  win/                      the Windows manifest every client compiles in
graal-<version>-<token>/    one folder per build (67, from graal-b1-19980906 to
                            graal-6.03r7-G3D0511C); four shown here
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

The GS1 language (`GGs1.pas`) is shared under that rule: it holds only the
language (parsing, statements, expressions, the command table), and what
each command does lives in the build's own NPC host (`Npc205`, `Npc217`,
...). A build uses it until it is found to read GS1 differently; then it
takes its own copy, as for any other unit. The NPC, baddy, sound, map and
editor units stay per build.

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

71 client folders: 67 Delphi rebuilds from the 1998 betas to 6.03r7, the
three Java clients and the Game Boy Color demo. Each folder's README has what works and a
"Not yet" checklist; [RELEASES.md](RELEASES.md) has each client's latest
release and level; [ROADMAP.md](ROADMAP.md) has the project checklist.

As of 2026-11-05: 2.05 rev 2 and 2.22 are at 0.0.2 (checked side by side
with the original), 2.17.1 at 0.0.1.1, every other client at 0.0.1. The
next release is v0.0.3 for all clients at once ([#99](https://github.com/squirelworks/graal-delphi/issues/99)).
The 3.x to 6.x folders reproduce the wire only and stay at 0.0.1 in level
until the Torque layer exists ([#109](https://github.com/squirelworks/graal-delphi/issues/109)).

## Windows says "Windows protected your PC"

The Windows exes are not code-signed yet, so the first time you start one
that came from a download, Microsoft Defender SmartScreen shows a blue
**"Windows protected your PC"** box with *Publisher: Unknown publisher*.
That is a reputation check, not a virus finding: SmartScreen stops any
downloaded program that is unsigned and that it has not seen many people
run. Any of these gets past it:

- **Run it once anyway.** Click **More info**, then **Run anyway**.
  Windows remembers that exe and does not ask again.
- **Unblock the zip before extracting it.** A browser marks every
  download as "from the internet" (the Mark of the Web), and Explorer
  copies that mark onto every file it extracts. Right-click the zip,
  **Properties**, tick **Unblock** at the bottom, **OK**, then extract.
  Nothing in the folder is asked about again.
- **Unblock a folder you already extracted**, in PowerShell:

  ```powershell
  Get-ChildItem -Recurse .\graal-2.22-GNW03014-v0.0.1-windows | Unblock-File
  ```

If Defender itself reports a threat (a red box, or the file vanishes)
that is a different thing: please open an issue with the name it gives.

### What the builds already do about it

Every Windows client carries a version block (product `graal-delphi`,
company `squirelworks`, the release version, a description naming the
build) and an application manifest (`common/win/graal-delphi.manifest`:
runs as the user, never asks for admin, declares Windows 7 to 11). They
set the DEP and ASLR flags, are not packed or compressed, and the zips
hold only the client, no test programs. That makes them look like an
ordinary program to SmartScreen and to antivirus heuristics, but it does
not remove the "Unknown publisher" box. Only a code signature does.

A new build folder gets its `src/<Program>.rc` and the `{$R}` line from
`python3 scripts/win/make_winres.py`; CI fails until it has them.

### Signing (what it would take)

SmartScreen only trusts a publisher, and a publisher is a code-signing
certificate from a certificate authority Windows trusts. A self-signed
certificate does nothing for anyone else's PC. The options:

- **Azure Trusted Signing** (Microsoft's own signing service, about
  US$10 a month). Individual developers can sign up (when last checked,
  only in the US and Canada) if they can pass
  Microsoft's identity check; it needs an Azure subscription, a Trusted
  Signing account, an identity validation, and a certificate profile.
  The release workflow would then sign each exe with Microsoft's
  `trusted-signing-action` before packing, using three repository
  secrets for an Azure app registration. Signed files build SmartScreen
  reputation quickly, often from the first release.
- **A standard (OV) code-signing certificate** from a CA such as
  Sectigo, DigiCert or SSL.com, roughly US$200 to 500 a year. Since 2023
  the key must live on a hardware token or in the CA's cloud signing
  service, so CI signs through the CA's cloud tool. OV certificates
  still start with no reputation: the box keeps showing until enough
  people have run the signed files.
- **SignPath Foundation** signs open-source projects for free, but the
  repository needs an OSI licence first (see Licence below: not chosen
  yet).

Whichever is chosen, the signing step goes in `.github/workflows/release.yml`
on the Windows job, between "Build and test" and "Pack".

## Licence

Not chosen yet.

## Every build is a GUI program

Each build opens a window with the start screen when started with no
arguments, as the original clients did: Training for the offline levels,
Start for the server list from the listserver, then account and password.
Flags still run it from the command line (stress runs, CI). Each build
carries stand-in assets in `common/builtin/`, all new art drawn by
`scripts/builtin/make_builtin.py` (no original file or pixel), so it runs
with nothing next to it; files from a real install next to the program,
or under `--data`, replace them.

A build plugs into `common/GStartScreen.pas` with:

- a `TListFetch` subclass for its listserver step (2.05: plain zlib, id 0
  `newmain`);
- a `TStartInfo`: the title lines, the background images to look for next
  to the program, and a callback that draws the character;
- its own front end, which picks the Training level and runs the game
  (see `RunGui` in `graal-2.05r2-GNW03081/src/Graal205.dpr`).

## One assets folder for every build

The original Graal files never go in this repository. Every rebuilt
program sits at the top of one folder (the root), and the player's
original files sit next to them in `graal-assets/`, extracted from one
zip kept outside the repo:

```
<root>/
  Graal205  Graal217  Graal222  ...
  graal-assets/
    common/     files the same in every version that has them
    2.05r2/     one folder per version line, named by the build's version label
    2.22/
```

A build looks for a file in the root (or `--data`), then in
`graal-assets/<version>/` and its fallback versions, then in
`graal-assets/common/`, and else uses its built-in assets
(`common/GAssetDirs.pas`). Nothing above the root is read. Graal 2.17.1
came in the same folder as 2.22, so its label is `2.17.1;2.22` and it
reads `graal-assets/2.22/` with no second copy.

The zip holds only what the rebuilt clients open, one version's install
per folder, never mixed across versions. [docs/assets.md](docs/assets.md)
has the search order per build, the keep/cut rule, how to build the zip
(`scripts/assets/merge_assets.py`, `scripts/assets/needed_assets.py`) and
what each client line's install held, from the 1998 betas on.
