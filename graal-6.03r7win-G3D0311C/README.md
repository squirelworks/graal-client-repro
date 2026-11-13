# Graal 6.03r7 for Windows (`G3D0311C`)

The Windows 6.03r7 client, rebuilt. The original is the Windows build of
November 2012: one Themida-protected executable built from the `quattro_lib`
engine, with no launcher and no engine library (graal_analysis
`protocol/v5v6-windows-unpacked.md`). It is the same release as the Linux
6.03r7 in `graal-6.03r7-G3D0511C`, but it sends its own token, so it is a
build of its own.

This folder starts as a copy of `graal-6.03r7-G3D0511C` and changes only what is
known to differ. The lab played the Windows 6.03r7 itself (graal_analysis
`protocol/v5v6-lab-play.md`), so the Login mode, the server warp and the
id set the Linux folder already follows come from this build. Only the
token and the Windows login tail change. This is the 0.0.1 reproduction: hit or miss.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

## Sources

| Area | Where |
|---|---|
| Token | seen on the wire: the real Windows 6.03r7 was run in the lab and sent `G3D0311C` (graal_analysis `protocol/v5v6-windows-unpacked.md`, "Tokens") |
| Login line, framing, ids both ways | graal_analysis `protocol/v6x-clients.md`, `protocol/v5v6-windows-unpacked.md` |
| Login mode, server warp, play | graal_analysis `protocol/v5v6-lab-play.md` |
| Everything carried over | `../graal-6.03r7-G3D0511C/README.md` |

## What differs from the 6.03r7 Linux rebuild

| | 6.03r7 Linux | 6.03r7 Windows (this folder) |
|---|---|---|
| Game token | `G3D0511C` | `G3D0311C` |
| Login line tail | `linux` and four machine fields | `win` and four machine fields |
| OSTYPE prop | `linux` | `win` |

Server ids handled: 92, the same set as 6.03r7 Linux (read from the unpacked Windows build).

## Units

As in `graal-6.03r7-G3D0511C`, with this folder's suffix: `Graal603w.dpr`, `Protocol603w`,
`ListServer603w`, `StartScreen603w`, `GraalClient`, `Adventure`, `RunMode`, and
6.03r7's provisional `GRESCR01` header probe as `Grescr603w` (no client call site).

## Running it

Put `Graal603w` in the root of a 6.03r7 Windows install and start it with no
arguments for the start screen. It finds the install's files from there,
or from `graal-assets/6.03r7 Windows/` and `graal-assets/common/` next to it.

Start asks a Seihai listserver for the server list (`listserver.txt` next
to the program, else `listserver.graal.in` on 14922), since the rebuild
cannot show the Login server's scripted list. The picked server's name
becomes the client's server name, as if the Login server had already
warped there, so the level and the player are drawn.

```
GRAAL_PW=... Graal603w --server HOST:PORT --account NAME            # as Login
GRAAL_PW=... Graal603w --server HOST:PORT --account NAME --server-name Classic
Graal603w --level some.nw                                          # offline
```

With `--server` and no `--server-name` the server is `Login`: no tiles and
no characters are drawn until the server sends a 178.

## Files it opens

From the program's folder (or `--data`), then `graal-assets/6.03r7 Windows/`, then
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

- [ ] The four Windows machine fields are sent as `""`; the original sends the MD5 of the product id, the adapter MAC and the `C:\` volume serial, then the quoted Windows version.
- [ ] The chat font (Tempus Sans ITC 24) and the 6.03r7 bomb drawing seen in the lab.
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
