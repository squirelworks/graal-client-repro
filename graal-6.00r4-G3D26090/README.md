# Graal 6.00r4 for Windows (`G3D26090`)

The Windows 6.00 rev 4 client, rebuilt. The original is one Themida-protected
executable built from the `quattro_lib` engine (compiled 26 June 2011), with
no launcher, no engine library and no bundled files (graal_analysis
`protocol/v5v6-windows-unpacked.md`). 6.00 rev 2 (12 June 2011) sends the
same token and handles the same ids, so this folder stands for both. The
folder `graal-5.31r4-G3D26090` shares the token too; the version part keeps
the two apart.

This folder starts as a copy of `graal-6.0.1.5-G3D3007A` and changes only what is
known to differ. 6.00r4 is the Windows build four months before 6.0.1.5, from the same
`quattro_lib` engine with the same login line. The lab ran 6.00r2 and 6.00r4
on real Windows (graal_analysis `protocol/v5v6-lab-play.md`, "6.00r2 and
6.00r4 on real Windows"): walk and hurt, after a server warp off `Login`. This is the 0.0.1 reproduction: hit or miss.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

## Sources

| Area | Where |
|---|---|
| Token | seen on the wire: the real 6.00r2 and 6.00r4 were run in the lab and sent `G3D26090` (graal_analysis `protocol/v5v6-windows-unpacked.md`, "Tokens") |
| Login line, framing, ids both ways | graal_analysis `protocol/v6x-clients.md`, `protocol/v5v6-windows-unpacked.md` |
| Login mode, server warp, play | graal_analysis `protocol/v5v6-lab-play.md` |
| Everything carried over | `../graal-6.0.1.5-G3D3007A/README.md` |

## What differs from the 6.0.1.5 Windows rebuild

| | 6.0.1.5 Windows | 6.00r4 (this folder) |
|---|---|---|
| Game token | `G3D3007A` | `G3D26090` |
| Server ids handled | 91 | 93: adds 175 and 184 |

Server ids handled: 93, read from the unpacked 6.00r2 and 6.00r4: the 6.0.1.5 rebuild's 91 plus 175 and 184, which the rebuild accepts and ignores.

## Units

As in `graal-6.0.1.5-G3D3007A`, with this folder's suffix: `Graal600r4.dpr`, `Protocol600r4`,
`ListServer600r4`, `StartScreen600r4`, `GraalClient`, `Adventure`, `RunMode`.

## Running it

Put `Graal600r4` in the root of a 6.00r4 install and start it with no
arguments for the start screen. It finds the install's files from there,
or from `graal-assets/6.00r4/` and `graal-assets/common/` next to it.

Start asks a Seihai listserver for the server list (`listserver.txt` next
to the program, else `listserver.graal.in` on 14922), since the rebuild
cannot show the Login server's scripted list. The picked server's name
becomes the client's server name, as if the Login server had already
warped there, so the level and the player are drawn.

```
GRAAL_PW=... Graal600r4 --server HOST:PORT --account NAME            # as Login
GRAAL_PW=... Graal600r4 --server HOST:PORT --account NAME --server-name Classic
Graal600r4 --level some.nw                                          # offline
```

With `--server` and no `--server-name` the server is `Login`: no tiles and
no characters are drawn until the server sends a 178.

## Files it opens

From the program's folder (or `--data`), then `graal-assets/6.00r4/`, then
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

- [ ] The beta expiry: the original logs "This is a beta release of Graal..." and exits unless the clock is set back to its build month. The rebuild has no expiry.
- [ ] 175 and 184 are accepted and ignored.
- [ ] The four Windows machine fields are sent as `""`; the original sends the MD5 of the product id, the adapter MAC and the `C:\` volume serial, then the quoted Windows version.
- [ ] No side-by-side run against the real client; that is 0.0.2 work.
- [ ] Everything still missing from `graal-6.0.1.5-G3D3007A`:

- [ ] The four Windows machine fields are sent as `""`; the original sends the MD5 of the product id, the adapter MAC and the `C:\` volume serial, then the quoted Windows version.

- [ ] The Login server's scripted GUI and GS2: 140 and 197 (scripts and the
  `GRESCR01` cache), 195 (gani scripts) and 190 are accepted and ignored.
- [ ] 109 (probably a file redirect) and 198 are accepted and ignored.
- [ ] 46 (ENTERLEVEL) on level entry, 162 (the ping answer), the base-file
  requests and the keep-alive 24 are not sent.
- [ ] `GR-V1.05` levels and `GRPKG001` update packages.
- [ ] The chat font (Tempus Sans ITC 24) and nickname colours by AP.
- [ ] Whether 6.01r1 plays offline at all is not traced; Training keeps 3.153's.
