# Graal 2.3 (`GNW14015`)

The 2.3 client, rebuilt. Original: Graal 2.3 (FileVersion 2.3.0.0), the
build before 2.31. This folder is a reproduction at **0.0.1**, and a
thinner one than its neighbours: no 2.3 executable has been read for the
notes yet (`version-profiles/2.22-2.31.md` marks every 2.3 value "as
2.31, inferred"), so this folder is the 2.31 rebuild
(`../graal-2.31-GNW28015`) with 2.3's token. A `Graal v2.3[Unpacked]`
copy has since turned up on the project's Drive, but it is flagged as
malware and is not used.

## What is 2.3's own here

| | 2.3 (this folder) | Source |
|---|---|---|
| Login token | `GNW14015` | `client-internals/version-tokens.md` |
| FileVersion | 2.3.0.0 | `client-internals/version-tokens.md` |
| Asset folders | `graal-assets/2.3/`, then `2.31/`, then `2.22/` | this repo's rule |
| Precise positions (X2 / Y2 / Z2), no classic mode, `LARGEFILESIZE` | from 2.3 on | GServer-v2 and the 2.3 release notes, via `2.22-2.31.md` |

Everything else is 2.31's, as the notes infer. See the 2.31 README for the
table of what differs from 2.22 (tamper timer, `ENTERLEVEL`, `SHOWIMG`,
the id and prop ranges, no `PUTNPC`).

## Stand-ins, to be checked against the 2.3 exe (0.0.2)

- **The tamper check bytes.** They are two CRC-32 words over each exe, so
  2.3's differ from 2.31's. The rebuild sends 2.31's
  (`291655b7602e87c9eb82`) until 2.3's are read. GServer-v2 and
  seihai-gserver read and discard them.
- The tamper timer (64 ticks), `ENTERLEVEL` (46), `SHOWIMG` (24) always,
  the 81 handled ids and the prop ranges: all 2.31's.
- 2.31's fixes that 2.3 lacked (NPCs crossing gmap borders, float to
  string in scripts, the key-config save) are not modelled in either
  folder, so the two behave the same here.
- `setmap`: GServer-v2 pushes the map files to 2.31 but not to 2.3, which
  suggests 2.3 still asked for them. The rebuild does not model `setmap`
  yet.
- The start window, the server list, the game window and the icon are
  2.31's (modelled on 2.31, the nearest real client): 2.31's pictures,
  buttons, icon and Training levels are compiled in from `res/` (see
  `res/README.md`), with 2.31's places and titles as seen under Wine. Whether
  2.3 already had the Editor button and the Graal Gold / Graal 3D / Classic
  / Hosted tabs is not known.

## Running it

The exe lives in the root: the folder that holds the game files as the
original install had them (`levels/`, `sounds/`, ...), or a
`graal-assets/` folder inside it. With nothing next to it, it runs on its
built-in stand-in art.

```
Graal230                                         # start screen
GRAAL_PW=... Graal230 --server HOST:PORT --account NAME
Graal230 --level some.nw --window                # offline
Graal230 --help
```

The listserver default is `listserver.graal.in` on 14922; `listserver.txt`
next to the program, or the install's `arrays2.dat`, wins over it.

## Checks

- `tests/Test230.dpr` (the 2.31 suite with `GNW14015`),
  `tests/TestSoundMap230.dpr`, `TestNpc230.pas`, `TestBaddy230.pas`.
- CI logs two of these into seihai-gserver (`scripts/loopback.sh`); the
  server names them `GNW14015 2.3`.
