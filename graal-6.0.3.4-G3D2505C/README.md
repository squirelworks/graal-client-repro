# Graal 6.0.3.4 for Windows (`G3D2505C`)

The 6.0.3.4 client, rebuilt. The original is `Graal6Setup.exe` from the
graalonline.com downloads of October 2012 (2,754,688 bytes, SHA-256
`f6df30178d99fdd97a70e855273cb1d500a482b65eb789d8c0d88a06e6a3c0d4`, PE
FileVersion 6.034, linked 2012-10-14): a self-installing client, one
protected executable, no launcher and no engine library.

This folder starts as a copy of `graal-6.03r7-G3D0511C` and changes only what is
known to differ. 6.0.3.4 is the Windows release a month before 6.03r7. Its protector hides
the code, so nothing beyond the token has been read from it yet; everything
else is 6.03r7's (the Linux build this folder starts from and the Windows
6.03r7 the lab played), with the Windows login tail the Windows 5.12 to
6.03r7 builds send. This is the 0.0.1 reproduction: hit or miss.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

## Sources

| Area | Where |
|---|---|
| The original's download, hashes and token | Batch-1 `Web-Discovered/METADATA.md` and `TOKENS.md` (2026-11-13) |
| Token | read from memory: the real 6.0.3.4 was run in a Windows 10 lab VM (2026-11-13) and `G3D2505C` was read from a dump of the running client, next to its "Connecting to the game server" text; it matches the public version list |
| Login line, framing, ids both ways | graal_analysis `protocol/v6x-clients.md`, `protocol/v5v6-windows-unpacked.md` |
| Login mode, server warp, play | graal_analysis `protocol/v5v6-lab-play.md` |
| Everything carried over | `../graal-6.03r7-G3D0511C/README.md` |

## What differs from the 6.03r7 Linux rebuild

| | 6.03r7 Linux | 6.0.3.4 (this folder) |
|---|---|---|
| Game token | `G3D0511C` | `G3D2505C` |
| Login line tail | `linux` and four machine fields | `win` and four machine fields |
| OSTYPE prop | `linux` | `win` |

Server ids handled: 92, taken from 6.03r7 (the Windows and Linux 6.03r7 sets are the same; not read from this build).

## Units

As in `graal-6.03r7-G3D0511C`, with this folder's suffix: `Graal6034.dpr`, `Protocol6034`,
`ListServer6034`, `StartScreen6034`, `GraalClient`, `Adventure`, `RunMode`, and
6.03r7's provisional `GRESCR01` header probe as `Grescr6034` (no client call site).

## Running it

Put `Graal6034` in the root of a 6.0.3.4 install and start it with no
arguments for the start screen. It finds the install's files from there,
or from `graal-assets/6.0.3.4/` and `graal-assets/common/` next to it.

Start asks a Seihai listserver for the server list (`listserver.txt` next
to the program, else `listserver.graal.in` on 14922), since the rebuild
cannot show the Login server's scripted list. The picked server's name
becomes the client's server name, as if the Login server had already
warped there, so the level and the player are drawn.

```
GRAAL_PW=... Graal6034 --server HOST:PORT --account NAME            # as Login
GRAAL_PW=... Graal6034 --server HOST:PORT --account NAME --server-name Classic
Graal6034 --level some.nw                                          # offline
```

With `--server` and no `--server-name` the server is `Login`: no tiles and
no characters are drawn until the server sends a 178.

## Files it opens

From the program's folder (or `--data`), then `graal-assets/6.0.3.4/`, then
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

- [ ] Nothing past the token has been read from 6.0.3.4 itself: its protector hides the code. The ids handled, the Login mode and the framing are 6.03r7's.
- [ ] The token was read from memory, not yet seen on the wire.
- [x] ~~The four Windows machine fields are sent as `""`~~: they now carry made-up MD5 hashes of SquirrelOS, SquirrelNIC and SquirrelBIOS strings, then the quoted Windows version, the shape the original sends.
- [ ] No side-by-side run against the real client; that is 0.0.2 work.
- [ ] Everything still missing from `graal-6.03r7-G3D0511C`:

- [ ] The Login server's scripted GUI and GS2: 140 and 197 (scripts and the
  `GRESCR01` cache), 195 (gani scripts) and 190 are accepted and ignored.
- [ ] 109 (probably a file redirect), 111 (`creationtime.dat`) and 198 are
  accepted and ignored; the rebuild writes no `creationtime.dat`.
- [ ] 46 (ENTERLEVEL) on level entry, 162 (the ping answer), the base-file
  requests and the keep-alive 24 are not sent.
- [ ] `GR-V1.05` levels and `GRPKG001` update packages.
- [ ] The chat font (Tempus Sans ITC 24) and nickname colours by AP.
- [ ] Whether 6.03r7 plays offline at all is not traced; Training keeps 3.153's.
- [x] Provisional standalone header probe and diagnostic-only want-script
  helpers, tested independently of the client.
- [ ] CRC/cache validation, client integration and script execution.
- [ ] Actual Quattro controls and level view; printing class names does
  not register controls or open a view.
- [ ] GS2 opcode bodies and wire ids; the 6.1.1.3 connector, UDP and
  package rows are not this folder.
