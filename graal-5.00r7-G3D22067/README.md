# Graal 5.00 rev 7 (`G3D22067`)

The 5.00r7 client, rebuilt. The original is the Windows build of July
2007: a Delphi launcher over a C++ engine library. On the wire it keeps the
gen-5 codec of 2.22 to 4.20, with its own token, no tamper check and no
listserver. This folder starts from `graal-3.153-G3D28015` and changes what
the 5.x notes say differs. This is the 0.0.1 reproduction: hit or miss.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

## Sources

From [graal_analysis](https://github.com/squirelworks/graal_analysis), not
from decompiled code:

| Area | Notes |
|---|---|
| Token, login line, ids handled, Login server | `protocol/v5x-clients.md` |
| Ids, props, login fields in table form | `version-profiles/5.00-6.03.toml` |
| Login mode, server warp, movement, timings | `version-profiles/lab-v5-2026-10-30.md` |
| What the server sends and the client answers | `protocol/v5v6-lab-play.md` |
| Everything carried over | `../graal-3.153-G3D28015/README.md`, `../graal-2.22-GNW03014/README.md` |

## What differs from the 3.153 rebuild

| | 3.153 | 5.00r7 (this folder) |
|---|---|---|
| Game token | `G3D28015` | `G3D22067` |
| Login line | ends at the password | then `win` and three machine fields (made-up hashes) |
| First frame | 5, 37, 34 bigmap, 34 minimap | 5 alone; 37 in its own gen-5 frame |
| Listserver | `G3D30123newmain` | none: the first server is a game server named `Login` |
| Login mode | no | while the server's name starts with "login", no characters are drawn |
| Server warp (178) | comma text | split on commas only; the name becomes the server's name |
| Server ids handled | 88 | 100: adds 105-107, 140, 170, 182, 183, 190, 191, 193-195, 197 |
| First props | 0, 18, 31, 33, 52, 75 `mac`, 76 | 0, 13, 52, 75 `win`, then X2 and Y2 |
| Movement | X and Y every other tick | X2 / Y2 (78, 79), pixels, every tick, only what changed |
| Process list (182) | not handled | answered with 44 |

The machine fields are MD5 hashes of the Windows product id, the adapter
MAC and the `C:` volume serial on the original. The rebuild reads none of
them and sends fixed made-up hashes of the same shape (MD5 hex of
SquirrelOS, SquirrelNIC and SquirrelBIOS strings). The real 5.00r7 sent
`""` for its MAC field in the lab, which had no network card. Its answer to 182 names only its own game window (the
server's name), not the processes on the machine.

## Units

As in 3.153, with the suffix `500`: `Protocol500`, `GraalClient`,
`Adventure`, `Graal500.dpr`, `ListServer500`, `StartScreen500`, `RunMode`.

## Running it

Put `Graal500` in the root of a 5.00r7 install and start it with no
arguments for the start screen. It finds the install's files from there,
or from `graal-assets/5.00r7/` and `graal-assets/common/` next to it.

Start asks a Seihai listserver for the server list (`listserver.txt` next
to the program, else `listserver.graal.in` on 14922), since the rebuild
cannot show the Login server's scripted list. The picked server's name
becomes the client's server name, as if the Login server had already
warped there, so the player is drawn.

```
GRAAL_PW=... Graal500 --server HOST:PORT --account NAME            # as Login
GRAAL_PW=... Graal500 --server HOST:PORT --account NAME --server-name Classic
Graal500 --level some.nw                                          # offline
```

With `--server` and no `--server-name` the server is `Login`: the level is
drawn, characters are not, until the server sends a 178.

## Files it opens

From the program's folder (or `--data`), then `graal-assets/5.00r7/`, then
`graal-assets/common/`:

- `pics1.png` (or `pics1.gif`) at the top or in `levels/tiles/`, where a
  5.00r7 install keeps it; `arrays.dat` (a 5.00r7 install has none, so the
  built-in tile types are used)
- `levels/` for levels, ganis and images; `levels/heads/`, `levels/bodies/`,
  `levels/swords/`, `levels/shields/`, `levels/hats/`, `levels/images/`,
  `levels/tiles/` and `levels/images/downloads/` (where the install keeps
  `sprites.png`)
- `levels/offlinetutorial_b-2.nw` (or `.graal`) for Training, else `start.nw`
  (a 5.00r7 install has no offline tutorial, so Training plays `start.nw`)
- `listserver.txt` (optional)

## Seihai secure login (not in the original)

Off by default, so the login is byte for byte the original's. With
`--secure-login auto` or `required` (or one word in `secure_login.txt` in
the shared settings folder), the account, the password and the platform fields after it go sealed to
a Seihai game server or list server (version token `SEI00001`,
graal-client-repro #148). Same code and settings as 2.31: see the 2.31
README, "Seihai secure login". CI logs in once more with
`--secure-login required` (`scripts/loopback.sh`).

## Not yet, or not known

- [ ] The Login server's scripted GUI (server list, accounts) and GS2 in
  general: 140 and 197 (class and weapon scripts, the `GRESCR01` cache),
  195 (gani scripts) and 190 (`onServerListerConnect`) are accepted and
  ignored.
- [ ] `GR-V1.05` levels (tile layers) and `GRPKG001` update packages.
- [ ] The base-file requests after the language (`basepackage.gupd` by 47 or 23).
- [ ] The keep-alive 24 the lab saw every 5 s: its payload was not recorded.
- [ ] 183 ("is this process running?") is accepted and not answered.
- [ ] Whether 5.00r7 plays offline at all is not traced; Training keeps 3.153's.
- [ ] The 3D mode (Torque, `Graal3DEngine.dll`, protocol 24).
- [ ] No side-by-side run against the real 5.00r7; that is 0.0.2 work.
- [ ] Everything still missing from the 3.153 rebuild.
