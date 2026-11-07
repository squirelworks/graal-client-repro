# Graal 6.03 rev 7 for Linux (`G3D0511C`)

The 6.03r7 client, rebuilt. The original read for this folder is the Linux
x64 build of November 2012: one native C++ program, no launcher and no
engine library. On the wire it keeps the gen-5 codec with its own token,
no tamper check, no listserver and no licence file. This folder starts
from `graal-5.00r7-G3D22067` and changes what the 6.x notes say differs.
This is the 0.0.1 reproduction: hit or miss.

The Windows 6.03r7 is the same release with its own token (`G3D0311C`) and
`win` in its login line. It is not this folder.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

## Sources

From [graal_analysis](https://github.com/squirelworks/graal_analysis), not
from decompiled code:

| Area | Notes |
|---|---|
| Token, login line, framing, ids both ways | `protocol/v6x-clients.md` |
| Ids in table form | `version-profiles/5.00-6.03.toml` |
| Login mode, server warp, play (Windows 6.03r7 in the lab) | `protocol/v5v6-lab-play.md` |
| Everything carried over | `../graal-5.00r7-G3D22067/README.md`, `../graal-3.153-G3D28015/README.md` |

## What differs from the 5.00r7 rebuild

| | 5.00r7 | 6.03r7 Linux (this folder) |
|---|---|---|
| Game token | `G3D22067` | `G3D0511C` |
| Login line tail | `win` and three machine fields | `linux` and four machine fields |
| Login mode | level drawn, no characters | no tiles and no characters (chests and image NPCs only) |
| Long frames | none | 0xFFFF bytes or more: length 0xFFFF, then a u32be length |
| Early flush | not traced (60000 bytes) | at 0x1000 bytes |
| Server ids handled | 100 | 92: drops 41, 75, 132, 133, 165, 169, 171, 175, 181, 184, 193; adds 109, 111, 198 |
| OSTYPE prop | `win` | `linux` (assumed from the login line) |

The machine ids are, on the original, MD5 hashes of the `eth0` MAC and of
the inode of `/etc`, an empty field, and the kernel release and version.
The rebuild reads none of them and sends each as `""`.

## Units

As in 5.00r7, with the suffix `603`: `Protocol603`, `GraalClient`,
`Adventure`, `Graal603.dpr`, `ListServer603`, `StartScreen603`, `RunMode`.
`Quattro603` records the 6.037 checks from `docs/v6-repro.md` that do not
need a script VM: the Windows image's stored token (not this folder's),
the generation-5 framer with no `setprotocol`, and the GS2 cases that
note names. It does not change the wire client.

## Running it

Put `Graal603` in the root of a 6.03r7 install and start it with no
arguments for the start screen. It finds the install's files from there,
or from `graal-assets/6.03r7/` and `graal-assets/common/` next to it.

Start asks a Seihai listserver for the server list (`listserver.txt` next
to the program, else `listserver.graal.in` on 14922), since the rebuild
cannot show the Login server's scripted list. The picked server's name
becomes the client's server name, as if the Login server had already
warped there, so the level and the player are drawn.

```
GRAAL_PW=... Graal603 --server HOST:PORT --account NAME            # as Login
GRAAL_PW=... Graal603 --server HOST:PORT --account NAME --server-name Classic
Graal603 --level some.nw                                          # offline
```

With `--server` and no `--server-name` the server is `Login`: no tiles and
no characters are drawn until the server sends a 178.

## Files it opens

From the program's folder (or `--data`), then `graal-assets/6.03r7/`, then
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

- [ ] The Login server's scripted GUI and GS2: 140 and 197 (scripts and the
  `GRESCR01` cache), 195 (gani scripts) and 190 are accepted and ignored.
- [ ] 109 (probably a file redirect), 111 (`creationtime.dat`) and 198 are
  accepted and ignored; the rebuild writes no `creationtime.dat`.
- [ ] 46 (ENTERLEVEL) on level entry, 162 (the ping answer), the base-file
  requests and the keep-alive 24 are not sent.
- [ ] `GR-V1.05` levels and `GRPKG001` update packages.
- [ ] The chat font (Tempus Sans ITC 24) and nickname colours by AP.
- [ ] Whether 6.03r7 plays offline at all is not traced; Training keeps 3.153's.
- [ ] No side-by-side run against the real 6.03r7; that is 0.0.2 work.
- [ ] Everything still missing from the 5.00r7 rebuild.
- [ ] GS2 opcode bodies, and the case numbers from 11 through 242 that
  `docs/v6-repro.md` does not name. `Quattro603` marks only the named
  ones. The 6.1.1.3 connector, UDP and package rows are not this folder.
