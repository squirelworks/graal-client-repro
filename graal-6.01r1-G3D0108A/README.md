# Graal 6.01 rev 1 for Linux (`G3D0108A`)

The 6.01r1 client, rebuilt. The original is the Linux build of September
2011 (x64 and x86): one native C++ program, no launcher and no engine
library. On the wire it keeps the gen-5 codec with its own token, no
tamper check, no listserver and no licence file. This folder starts from
`graal-6.03r7-G3D0511C` and changes what the 6.x notes say differs. 6.01r1
was never run in the lab; where its behaviour is not read from the binary,
the 6.03r7 lab run is taken to hold. This is the 0.0.1 reproduction: hit
or miss.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

## Sources

From [graal_analysis](https://github.com/squirelworks/graal_analysis), not
from decompiled code:

| Area | Notes |
|---|---|
| Token, login line, framing, ids both ways | `protocol/v6x-clients.md` |
| Login mode, server warp, play (Windows 6.03r7, standing in) | `protocol/v5v6-lab-play.md` |
| Everything carried over | `../graal-6.03r7-G3D0511C/README.md`, `../graal-5.00r7-G3D22067/README.md` |

## What differs from the 6.03r7 rebuild

| | 6.03r7 Linux | 6.01r1 Linux (this folder) |
|---|---|---|
| Game token | `G3D0511C` | `G3D0108A` |
| Server ids handled | 92 | 91: no 111 (`creationtime.dat`) |

Everything else is 6.03r7's: the login line ends with `linux` and four
machine fields (sent as `""`), Login mode draws no tiles and no characters
(taken from the 6.03r7 lab run), long frames, the flush at 0x1000 bytes,
OSTYPE `linux`. 6.01r1 also does not send 160 (folder delete), which the
rebuild never sends anyway.

seihai-core has no profile for `G3D0108A`, so `scripts/loopback.sh` now
adds the build's own token to the test world's allowed versions.

## Units

As in 6.03r7, with the suffix `601`: `Protocol601`, `GraalClient`,
`Adventure`, `Graal601.dpr`, `ListServer601`, `StartScreen601`, `RunMode`.

## Running it

Put `Graal601` in the root of a 6.01r1 install and start it with no
arguments for the start screen. It finds the install's files from there,
or from `graal-assets/6.01r1/` and `graal-assets/common/` next to it.

Start asks a Seihai listserver for the server list (`listserver.txt` next
to the program, else `listserver.graal.in` on 14922), since the rebuild
cannot show the Login server's scripted list. The picked server's name
becomes the client's server name, as if the Login server had already
warped there, so the level and the player are drawn.

```
GRAAL_PW=... Graal601 --server HOST:PORT --account NAME            # as Login
GRAAL_PW=... Graal601 --server HOST:PORT --account NAME --server-name Classic
Graal601 --level some.nw                                          # offline
```

With `--server` and no `--server-name` the server is `Login`: no tiles and
no characters are drawn until the server sends a 178.

## Files it opens

From the program's folder (or `--data`), then `graal-assets/6.01r1/`, then
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
- [ ] No side-by-side run against the real 6.01r1; that is 0.0.2 work.
- [ ] Everything still missing from the 6.03r7 rebuild.
