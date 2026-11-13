# Graal 6.00 beta 2 for Windows (`G3D15010`)

The Windows 6.00 beta 2 client, rebuilt. The original is one MSVC
executable built from the `quattro_lib` engine (compiled 15 January 2010) in
a MoleBox wrapper that serves its 65 bundled files from memory (graal_analysis
`protocol/v5v6-windows-unpacked.md`). It came a week after 6.00 beta 1 and a
week before 5.24r3, and it sends the same token as 5.24r3 and 5.24r4,
`G3D15010`: the 6.00 and 5.24 lines shared one code base in early 2010.

This folder starts as a copy of `graal-6.00b1-G3D03048` (itself from
`graal-6.0.1.5-G3D3007A`) and changes only the token. Its id set and login
line are those of 6.00 beta 1 and 5.24, which the lab played. The lab ran it
to the login only (graal_analysis `protocol/v5v6-lab-play.md`), so the Login
mode with tiles is 5.24's. This is the 0.0.1 reproduction: hit or miss.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

## Sources

| Area | Where |
|---|---|
| Token | seen on the wire: the real 6.00 beta 2 was run in the lab and sent `G3D15010` (graal_analysis `protocol/v5v6-windows-unpacked.md`, "Tokens") |
| Login line, framing, ids both ways | graal_analysis `protocol/v6x-clients.md`, `protocol/v5v6-windows-unpacked.md` |
| Login mode, server warp, play | graal_analysis `protocol/v5v6-lab-play.md` |
| Everything carried over | `../graal-6.00b1-G3D03048/README.md`, `../graal-6.0.1.5-G3D3007A/README.md` |

## What differs from the 6.0.1.5 Windows rebuild

| | 6.0.1.5 Windows | 6.00 beta 2 (this folder) |
|---|---|---|
| Game token | `G3D3007A` | `G3D15010` |
| Server ids handled | 91 | 97: adds 41, 165, 169, 175, 181 and 184 |
| Login mode | no tiles, no characters | tiles drawn, no characters (taken from 5.24) |

Server ids handled: 97, read from the unpacked 6.00 beta 1 (the same set as 6.00 beta 2 and 5.24): the 6.0.1.5 rebuild's 91 plus 41, 165, 169, 175, 181 and 184, which the rebuild accepts and ignores.

## Units

As in `graal-6.0.1.5-G3D3007A`, with this folder's suffix: `Graal600b2.dpr`, `Protocol600b2`,
`ListServer600b2`, `StartScreen600b2`, `GraalClient`, `Adventure`, `RunMode`.

## Running it

Put `Graal600b2` in the root of a 6.00b2 install and start it with no
arguments for the start screen. It finds the install's files from there,
or from `graal-assets/6.00b2/` and `graal-assets/common/` next to it.

Start asks a Seihai listserver for the server list (`listserver.txt` next
to the program, else `listserver.graal.in` on 14922), since the rebuild
cannot show the Login server's scripted list. The picked server's name
becomes the client's server name, as if the Login server had already
warped there, so the level and the player are drawn.

```
GRAAL_PW=... Graal600b2 --server HOST:PORT --account NAME            # as Login
GRAAL_PW=... Graal600b2 --server HOST:PORT --account NAME --server-name Classic
Graal600b2 --level some.nw                                          # offline
```

With `--server` and no `--server-name` the server is `Login`: the tiles are
drawn but no characters until the server sends a 178.

## Files it opens

From the program's folder (or `--data`), then `graal-assets/6.00b2/`, then
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

- [ ] Played only to the login in the lab; the Login mode and play are 5.24's.
- [ ] 41, 165, 169, 175, 181 and 184 are accepted and ignored.
- [ ] The bundled files: the original serves 65 files from its MoleBox wrapper; the rebuild reads an install or `graal-assets/`.
- [ ] Long frames and the 0x1000 flush are 6.x's; not traced in the 6.00 betas.
- [x] ~~The four Windows machine fields are sent as `""`~~: they now carry made-up MD5 hashes of SquirrelOS, SquirrelNIC and SquirrelBIOS strings, then the quoted Windows version, the shape the original sends.
- [ ] No side-by-side run against the real client; that is 0.0.2 work.
- [ ] Everything still missing from `graal-6.0.1.5-G3D3007A`:

- [x] ~~The four Windows machine fields are sent as `""`~~: they now carry made-up MD5 hashes of SquirrelOS, SquirrelNIC and SquirrelBIOS strings, then the quoted Windows version, the shape the original sends.

- [ ] The Login server's scripted GUI and GS2: 140 and 197 (scripts and the
  `GRESCR01` cache), 195 (gani scripts) and 190 are accepted and ignored.
- [ ] 109 (probably a file redirect) and 198 are accepted and ignored.
- [ ] 46 (ENTERLEVEL) on level entry, 162 (the ping answer), the base-file
  requests and the keep-alive 24 are not sent.
- [ ] `GR-V1.05` levels and `GRPKG001` update packages.
- [ ] The chat font (Tempus Sans ITC 24) and nickname colours by AP.
- [ ] Whether 6.01r1 plays offline at all is not traced; Training keeps 3.153's.
