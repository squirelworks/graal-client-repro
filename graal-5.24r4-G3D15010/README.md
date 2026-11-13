# Graal 5.24r4 for Windows (`G3D15010`)

The Windows 5.24 rev 4 client, rebuilt. The original is one MSVC
executable built from the `quattro_lib` engine (compiled 1 February 2010) in
a MoleBox wrapper that serves its 65 bundled files from memory, with no
Delphi launcher and no engine library (graal_analysis
`protocol/v5v6-windows-unpacked.md`). 5.24 rev 3 (22 January 2010) and
6.00 beta 2 (15 January 2010) send the same token and handle the same ids,
so this folder stands for all three.

This folder starts as a copy of `graal-6.0.1.5-G3D3007A` and changes only what is
known to differ. 5.24 is the first one-exe `quattro_lib` build, the line 6.0.1.5 grew from,
with the same login line (`win`, three MD5 fields and the quoted Windows
version). The lab played 5.24r4 in full (graal_analysis
`protocol/v5v6-lab-play.md`): unlike 5.31r4 and 6.x it draws the tiles in
Login mode too, before any server warp. This is the 0.0.1 reproduction: hit or miss.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

## Sources

| Area | Where |
|---|---|
| Token | seen on the wire: the real 5.24r3, 5.24r4 and 6.00 beta 2 were run in the lab and sent `G3D15010` (graal_analysis `protocol/v5v6-windows-unpacked.md`, "Tokens") |
| Login line, framing, ids both ways | graal_analysis `protocol/v6x-clients.md`, `protocol/v5v6-windows-unpacked.md` |
| Login mode, server warp, play | graal_analysis `protocol/v5v6-lab-play.md` |
| Everything carried over | `../graal-6.0.1.5-G3D3007A/README.md` |

## What differs from the 6.0.1.5 Windows rebuild

| | 6.0.1.5 Windows | 5.24r4 (this folder) |
|---|---|---|
| Game token | `G3D3007A` | `G3D15010` |
| Server ids handled | 91 | 97: adds 41, 165, 169, 175, 181 and 184 |
| Login mode | no tiles, no characters | tiles drawn, no characters (5.24 in the lab) |

Server ids handled: 97, read from the unpacked 6.00 beta 2, 5.24r3 and 5.24r4: the 6.0.1.5 rebuild's 91 plus 41, 165, 169, 175, 181 and 184, which the rebuild accepts and ignores.

## Units

As in `graal-6.0.1.5-G3D3007A`, with this folder's suffix: `Graal524r4.dpr`, `Protocol524r4`,
`ListServer524r4`, `StartScreen524r4`, `GraalClient`, `Adventure`, `RunMode`.

## Running it

Put `Graal524r4` in the root of a 5.24r4 install and start it with no
arguments for the start screen. It finds the install's files from there,
or from `graal-assets/5.24r4/` and `graal-assets/common/` next to it.

Start asks a Seihai listserver for the server list (`listserver.txt` next
to the program, else `listserver.graal.in` on 14922), since the rebuild
cannot show the Login server's scripted list. The picked server's name
becomes the client's server name, as if the Login server had already
warped there, so the level and the player are drawn.

```
GRAAL_PW=... Graal524r4 --server HOST:PORT --account NAME            # as Login
GRAAL_PW=... Graal524r4 --server HOST:PORT --account NAME --server-name Classic
Graal524r4 --level some.nw                                          # offline
```

With `--server` and no `--server-name` the server is `Login`: the tiles are
drawn but no characters until the server sends a 178.

## Files it opens

From the program's folder (or `--data`), then `graal-assets/5.24r4/`, then
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

- [ ] 41, 165, 169, 175, 181 and 184 are accepted and ignored.
- [ ] The bundled files: the original serves 65 files from its MoleBox wrapper; the rebuild reads an install or `graal-assets/`.
- [ ] The chat font (Arial, from its config) and the large flame cross it draws for a bomb.
- [ ] Long frames and the 0x1000 flush are 6.x's; not traced in 5.24.
- [ ] The four Windows machine fields are sent as `""`; the original sends the MD5 of the product id, the adapter MAC and the `C:\` volume serial, then the quoted Windows version.
- [ ] No side-by-side run against the real client; that is 0.0.2 work.
- [ ] Everything still missing from `graal-6.0.1.5-G3D3007A`:

- [ ] Nothing past the token has been read from 6.0.1.5 itself: its protector hides the code. The ids handled, the Login mode and the framing are 6.01r1's.
- [ ] The four Windows machine fields are sent as `""`; the original sends the MD5 of the product id, the adapter MAC and the `C:\` volume serial, then the quoted Windows version.
- [ ] 6.0.0.7 is not checked separately; it is taken to behave as 6.0.1.5.

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
