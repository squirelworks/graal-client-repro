# Graal 6.x beta of 2011-06-27 for Linux (`G3D28090`)

The Linux 6.x beta of 27 June 2011, rebuilt. The originals are
`Graal_linux32.zip` and `Graal_linux64.zip` from the official
beta downloads of June 2011: each holds one program
named `Graal` (x86: 6,238,344 bytes, SHA-256
`72643e8c2ef6f104e909d01ea8007923161aabdfb579450a4b9e1ac9d95fe879`; x64:
6,516,336 bytes, SHA-256
`cef479ec60b244eeda1f03a8cf774fe17d40c981ea76f82d8bd127b07fb7dcde`), one
native C++ program with no launcher and no engine library. Neither carries
a version string. The Mac and Windows downloads in the same folder that day
are 6.004 (6.00 rev 4), so this is probably the Linux 6.00r4; the folder
name keeps the date because the version is not in the download.

This folder starts as a copy of `graal-6.01r1-G3D0108A` and changes only what is
known to differ. The beta is three months older than the 6.01r1 this folder starts from,
and the same program family (one native C++ program, `linux` in the login
line). Only the token differs so far. This is the 0.0.1 reproduction: hit or miss.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

## Sources

| Area | Where |
|---|---|
| The original's download, hashes and token | Batch-1 `Web-Discovered/METADATA.md` and `TOKENS.md` (2026-11-13) |
| Token | read from the binary: both programs build `G3D28090` in their connect routine (static read, 2026-11-13, by the method checked against six tokens already seen on the wire) |
| Login line, framing, ids both ways | graal_analysis `protocol/v6x-clients.md`, `protocol/v5v6-windows-unpacked.md` |
| Login mode, server warp, play | graal_analysis `protocol/v5v6-lab-play.md` |
| Everything carried over | `../graal-6.01r1-G3D0108A/README.md` |

## What differs from the 6.01r1 Linux rebuild

| | 6.01r1 Linux | 6.x beta (2011-06-27) (this folder) |
|---|---|---|
| Game token | `G3D0108A` | `G3D28090` |

Server ids handled: 91, taken from 6.01r1 Linux (not read from this build; the Windows 6.00r4 handles 93, the same plus 175 and 184).

## Units

As in `graal-6.01r1-G3D0108A`, with this folder's suffix: `Graal600b.dpr`, `Protocol600b`,
`ListServer600b`, `StartScreen600b`, `GraalClient`, `Adventure`, `RunMode`.

## Running it

Put `Graal600b` in the root of a 6.00beta-20110627 install and start it with no
arguments for the start screen. It finds the install's files from there,
or from `graal-assets/6.00beta-20110627/` and `graal-assets/common/` next to it.

Start asks a Seihai listserver for the server list (`listserver.txt` next
to the program, else `listserver.graal.in` on 14922), since the rebuild
cannot show the Login server's scripted list. The picked server's name
becomes the client's server name, as if the Login server had already
warped there, so the level and the player are drawn.

```
GRAAL_PW=... Graal600b --server HOST:PORT --account NAME            # as Login
GRAAL_PW=... Graal600b --server HOST:PORT --account NAME --server-name Classic
Graal600b --level some.nw                                          # offline
```

With `--server` and no `--server-name` the server is `Login`: no tiles and
no characters are drawn until the server sends a 178.

## Files it opens

From the program's folder (or `--data`), then `graal-assets/6.00beta-20110627/`, then
`graal-assets/common/`:

- `pics1.png` (or `pics1.gif`) at the top or in `levels/tiles/`, where a
  5.x/6.x install keeps it; `arrays.dat` (a 5.x/6.x install has none, so
  the built-in tile types are used)
- `levels/` for levels, ganis and images; `levels/heads/`, `levels/bodies/`,
  `levels/swords/`, `levels/shields/`, `levels/hats/`, `levels/images/`,
  `levels/tiles/` and `levels/images/downloads/` (where the install keeps
  `sprites.png`)
- `levels/offlinetutorial_b-2.nw` (or `.graal`) for Training, else `start.nw`
  (a 5.x/6.x install has no offline tutorial, so Training plays `start.nw`)
- `listserver.txt` (optional)

## Not yet, or not known

- [ ] Nothing past the token has been read from the beta yet. The ids handled, the Login mode and the framing are 6.01r1's.
- [ ] Whether it has the beta expiry the Windows 6.00r2 and 6.00r4 have ("This is a beta release of Graal...", the only related text in the program) is not traced.
- [ ] The token was read from the program, not yet seen on the wire.
- [ ] The version: probably 6.00r4, from the same-day Mac and Windows downloads, not from the program.
- [ ] No side-by-side run against the real client; that is 0.0.2 work.
- [ ] Everything still missing from `graal-6.01r1-G3D0108A`:

- [ ] Whether 6.01r1 draws tiles in Login mode: not recorded; 6.03r7's "no" is
  used.
- [ ] The Login server's scripted GUI and GS2: 140 and 197 (scripts and the
  `GRESCR01` cache), 195 (gani scripts) and 190 are accepted and ignored.
- [ ] 109 (probably a file redirect) and 198 are accepted and ignored.
- [ ] 46 (ENTERLEVEL) on level entry, 162 (the ping answer), the base-file
  requests and the keep-alive 24 are not sent.
- [ ] `GR-V1.05` levels and `GRPKG001` update packages.
- [ ] The chat font (Tempus Sans ITC 24) and nickname colours by AP.
- [ ] Whether 6.01r1 plays offline at all is not traced; Training keeps 3.153's.
