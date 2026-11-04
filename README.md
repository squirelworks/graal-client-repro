# graal-delphi

Faithful rebuilds of the classic Graal Online clients, one per build, in the
language they were written in: Delphi (Object Pascal). Each rebuild aims to
behave like the original on the wire and on screen, and then gets hardened
so it can run in large test runs.

The findings these rebuilds are based on live in
[graal_analysis](https://github.com/squirelworks/graal_analysis). The
servers they are tested against are the Seihai stack, mainly
[seihai-gserver](https://github.com/squirelworks/seihai-gserver).

This repo holds no original Graal code, graphics, or level data. Assets
such as `pics1.png` are loaded from your own install at run time.

## Layout

```
common/                     code that is the same across builds
  GTypes.pas                GCHAR / GSHORT / GINT3..5 / GSTRING, message reader
  GZlib.pas                 zlib in and out of string buffers
  GSocket.pas               non-blocking TCP, polled from the game tick
  GLevel.pas                64x64 level: GR-V1.0x, Z3-V1.0x, GLEVNW01, board packet, GR-V writer
  GSurface.pas              32-bit software surface, tile sheet blit, BMP/PNG/GIF loading
graal-2.05r2-GNW03081/      Graal 2.05 rev 2
  src/                      the client (Graal205.dpr and its units)
  tests/                    Test205.dpr
scripts/
  build.sh                  build every rebuild and its tests
  test.sh                   run every test program
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
  in CI, on Linux and Windows.
- **Delphi**: the units avoid anything newer than Delphi 5 (no generics, no
  inline variables, `string` used as a byte buffer as in 2001-era code), and
  take the Delphi path under `{$IFNDEF FPC}` (WinSock, the Borland `ZLib`
  unit). 2.05 itself was built with Delphi 4 or 5 and DelphiX. A Delphi 5
  or 7 build has not been tried yet; it is the next toolchain check.
- DelphiX (DirectDraw) does not build outside Windows or under Free Pascal,
  so the rebuilds draw into a software surface (`GSurface`) and a front end
  shows it. For now the front end writes a `.bmp`; a window comes later.

## Build, test, run

```
sudo apt-get install fp-compiler fp-units-base fp-units-fcl
scripts/build.sh
scripts/test.sh

# offline: draw a level
build/graal-2.05r2-GNW03081/Graal205 --level some.graal --sheet path/to/pics1.png --dump frame.bmp

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
   release. The tag is the folder name (`graal-2.05r2-GNW03081`), and the
   release carries the built Linux and Windows binaries. Pushing the tag
   runs `.github/workflows/release.yml`, which builds that one folder and
   attaches the binaries.

## Status

| Build | Token | Wire | World | Play | Harden | Release |
|---|---|---|---|---|---|---|
| [2.05 rev 2](graal-2.05r2-GNW03081/) | `GNW03081` | done | board drawn, player marker | not started | not started | not yet |

## Licence

Not chosen yet.
