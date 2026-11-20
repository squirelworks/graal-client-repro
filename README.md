# graal-client-repro

Faithful rebuilds of the classic Graal clients, one per build, in the language
they were written in: Delphi (Object Pascal). The rebuilt programs carry the
name graal-delphi. Each rebuild aims to behave like the original, on the wire
and in play, and is then hardened so it can run in large test runs. Matching
the original's look is not a goal ([docs/functional-parity.md](docs/functional-parity.md)).

The findings these rebuilds are based on are in
[Graal_analysis](https://github.com/squirelworks/Graal_analysis). They are tested
against the Seihai server stack, mainly
[seihai-gserver](https://github.com/squirelworks/seihai-gserver).

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad"). "Graal",
> "Graal Online" and related names are trademarks of their respective
> owners and are used here only to identify the software being
> reimplemented.

## Status

There are 80 client folders: 76 Graal builds, from the 1998 betas to the seven
Worlds builds (548 to 7.0.1.7.5.0), plus the three Java clients and the Game Boy
Color demo. The Graal builds are Object Pascal rebuilds, except that 3.04 and
4.20r8 also carry C++ boot hosts (`common/torque/host304`, `host4208`) and Worlds
614 is a portable C# stand-in for a Unity player. The other six Worlds builds are
only scaffolds so far, and several real builds have no folder yet (see
"Builds with no folder" in [ROADMAP.md](ROADMAP.md)).

The 3.x to 6.x folders reproduce the wire protocol and each client's behaviour.
The Torque engine around the 3.x to early 5.x clients is being rebuilt in C++
under `common/torque/`
([#109](https://github.com/squirelworks/graal-client-repro/issues/109)).

Each build folder's README says what works and has a "Not yet" checklist.
The latest combined release is
[v0.0.4.2](https://github.com/squirelworks/graal-client-repro/releases/tag/v0.0.4.2)
(2026-11-13); the next one planned is 0.0.5.

## Download and run

Each client's latest release, for Linux, Windows and macOS, is listed in
[RELEASES.md](RELEASES.md) and on the
[Releases page](https://github.com/squirelworks/graal-client-repro/releases).

Each build opens a window with the start screen when started with no
arguments, as the original clients did: Training for the offline levels,
Start for the server list from the listserver, then account and password.
Flags still run it from the command line (stress runs, CI). Each build
carries stand-in assets in `common/builtin/`, all new art drawn by
`scripts/builtin/make_builtin.py` (no original file or pixel), so it runs
with nothing next to it; files from a real install next to the program,
or under `--data`, replace them.

The Windows programs are not code-signed yet, so the first time you start one
from a download, Microsoft Defender SmartScreen shows a blue **"Windows protected
your PC"** box. Click **More info**, then **Run anyway**; or, before extracting,
right-click the zip, choose **Properties**, tick **Unblock** and press **OK**.
[docs/windows-smartscreen.md](docs/windows-smartscreen.md) explains why it
happens and what the builds already do about it. If Defender reports an actual
threat (a red box, or the file disappears), please open an issue with the name
it gives.

## Your Graal files

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

### Original art: `assets/`

The pictures and levels each program carries in its resources (start
screens, picture buttons, glyphs, icon, cursors, Training levels) are
graal-delphi's own art, drawn in the originals' sizes and formats by
`scripts/art/make_art.py` ([docs/art.md](docs/art.md)). To see a
program's original art, put its files in an `assets/` folder beside the
program; they win over the carried art and over `graal-assets/`, with no
rebuild:

```
python3 -I scripts/art/to_assets.py path/to/your/Graal.exe <root>/assets 2.05r2
```

That writes the exe's own resources to `assets/2.05r2/res/` (game files
such as `pics1.png` can go in `assets/2.05r2/` or `assets/` too).
[docs/assets.md](docs/assets.md), "Your own files", has the details. These
files are yours: never commit them.
## Building from source

### Toolchain

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

### Build, test, run

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

## How the repository is organised

`common/` holds the code that is the same in every build, and each build has its
own folder named `graal-<version>-<token>`, such as `graal-2.05r2-GNW03081/`.
Every build goes through the same five phases, from the wire protocol to a
release. The full layout, the folder naming rule, what may go in `common/`, how
a build plugs into the shared start screen and the phases are in
[docs/repo-layout.md](docs/repo-layout.md).

## Contributing

Read [AGENTS.md](AGENTS.md) for the project rules, [ROADMAP.md](ROADMAP.md) for
what is next, and [HANDOFF-CURSOR.md](HANDOFF-CURSOR.md) for the current state,
work on hold and open decisions.

## Provenance

What is in this repo and where it came from. The project may carry some
original Graal material, as described here.

- **Written from notes.** The client code (the Pascal rebuilds, the
  launchers and start screens, the C++ engine hosts, the Quattro program
  and the GS2 VM under `common/cpp/gs2/`) is written from the behaviour
  notes in [graal_analysis](https://github.com/squirelworks/graal_analysis)
  on the wire protocol, file formats and observed behaviour, and from the
  project's own lab runs. It is not copied or translated from the original
  programs. `common/torque/PROVENANCE.md` details the Torque layer.
- **Original resources: their shape carried, their art replaced.** Each
  build carries its own exe's resources (icons, cursors, bitmaps, dialogs
  and form layouts, menus, string tables, version info, and the few levels
  an exe embeds, such as the Training and online start levels) under the
  original names, sizes and formats, in its `res/` (or `src/res/`) folder,
  the generated `Res*.pas` / `RealRes*.pas` units and `common/GRes20x.pas`.
  Since 2026-11-19 every picture,
  icon, cursor and level among them is graal-delphi's own art, drawn by
  `scripts/art/make_art.py` ([docs/art.md](docs/art.md)); CI checks it.
  The text resources (form layouts and captions, string tables, character
  lists, the 2.22 language file) are still the originals', because the
  code reads them; whether to rewrite them is open. A player's own
  originals go in `assets/` beside the program (see [Your Graal files](#your-graal-files)).
- **Not carried.** Game data (`pics1.png`, `arrays.dat`, ganis, heads,
  bodies, levels, sounds) is loaded at run time from an install you supply
  (`graal-assets/`, [docs/assets.md](docs/assets.md)). The built-in
  defaults in `common/builtin/` are new art drawn by
  `scripts/builtin/make_builtin.py`, not original files. Tests that need
  original data, such as the tutorial levels inside the 2.05 exe, read it
  from a local path and are skipped when it is missing.
- **List server.** Builds that fetch a server list default to the
  community list server `listserver.graal.in`; the original hosts are
  defunct.
- **Third-party code.** The Torque3D string Huffman frequency table and
  tree build (MIT) in `common/cpp/third_party/torque3d/`, with its
  copyright notice and licence in `LICENSE.txt` there. The system zlib and
  bzip2 libraries are linked, not vendored.

## Licence

[Apache License 2.0](LICENSE), the same as the Seihai server stack. Unless
you say otherwise, a contribution you submit is licensed the same way. The
licence covers the project's own code and the stand-in assets in this repo.
It does not cover the original text resources still carried in the
`res/` folders and the units generated from them (see Provenance), and it grants
no rights to Graal's names or to any original Graal file. The licence
decision itself is open in
[#116](https://github.com/squirelworks/graal-client-repro/issues/116).
