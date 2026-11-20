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

## Repro tracks

Policy: [docs/engine-repro-policy.md](../docs/engine-repro-policy.md).

- **default:** Delphi/Pascal stand-in (no-argument / release entry on main today).
- **faithful engine:** Quattro `quattro-play` sibling path — still being wired; not the release default.
- **relic:** none yet. When the faithful engine is validated end-to-end and switched to default, the Pascal stand-in becomes the labeled relic/fallback and is never deleted.

## Sources

From [graal_analysis](https://github.com/squirelworks/graal_analysis), not
from decompiled code:

| Area | Notes |
|---|---|
| Token, login line, framing, ids both ways | `protocol/v6x-clients.md` |
| Ids in table form | `version-profiles/5.00-6.03.toml` |
| Login mode, server warp, play (Windows 6.03r7 in the lab) | `protocol/v5v6-lab-play.md` |
| The rebuild end to end through the Seihai suite (2026-11-20) | [docs/e2e-lab-2026-11-20.md](docs/e2e-lab-2026-11-20.md) (this repo) |
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
The rebuild reads none of them. It sends fixed made-up values of the same
shape: MD5 hex of SquirrelNIC and SquirrelFS strings, the empty field, and
the SquirrelOS kernel string
`2.6.38-1-squirrelos  #1-SquirrelOS SMP Mon Jun 27 12:00:00 UTC 2011`.

## Units

As in 5.00r7, with the suffix `603`: `Protocol603`, `GraalClient`,
`Adventure`, `Graal603.dpr`, `ListServer603`, `StartScreen603`, `RunMode`.
The Linux token stays `G3D0511C`. No Torque engine is linked.

Observed: `docs/v6-repro.md` identifies the original Windows 6.0.3.7
engine as `quattro_lib` and documents GS2 magic and CRC coverage.
This Pascal rebuild does not implement that engine.

Provisional: `Grescr603` is a standalone header probe tested independently
of the client, with no client call site. It checks eight bytes of magic
and records the tail byte count. Passing is not script acceptance: CRC,
cache flags, decoding and execution remain unimplemented. An eight-byte
header alone passes the probe; original-loader acceptance is unknown.
The three want-script helpers return diagnostic strings only. They
raise no event and send no packet. Wire ids are unknown (`id=unknown`).

## Running it

On Linux the game itself runs in `quattro-play`, the rebuilt Quattro
program (`common/cpp/quattro`), which `scripts/build.sh` puts next to
`Graal603`: the start screen picks the server or Training and hands the game
over (`common/GQuattroPlay.pas`), then comes back when it ends. Set
`GRAAL_PASCAL_GAME=1` to play in this folder's own Pascal game instead,
as Windows and a machine with no X display always do.

On Linux, `--window` also hands compatible command-line games to the same
player. The supported subset is `--server HOST:PORT --account NAME`
with optional `--password-env` and `--server-name`, or `--level FILE`
with optional `--x` and `--y`; both accept `--data` and a positive integer
`--seconds`. Passwords travel in the child environment, never arguments.
Online secure-login settings still keep the game in Pascal; explicit
`--secure-login off` selects the original-login route. Quattro returns its
own exit status and online output, rather than the Pascal JSON summary.
No arguments still opens the Pascal start screen.

Headless games, `--frames`, scripted movement, dumps, statistics, custom
tile sheets and other unsupported or malformed options retain the Pascal
CLI. They are not silently dropped or translated into different timing.
Shared installs containing `_clients` also retain Pascal's file allow-list.
The missing-player, no-display and `GRAAL_PASCAL_GAME=1` fallbacks apply
to windowed command-line games too. This is rebuild routing, not recovery
of the original executable's startup dialogs or connection-event dispatch.

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

## Seihai secure login (not in the original)

Off by default, so the login is byte for byte the original's. With
`--secure-login auto` or `required` (or one word in `secure_login.txt` in
the shared settings folder), the account, the password and the platform fields after it go sealed to
a Seihai game server or list server (version token `SEI00001`,
graal-client-repro #148). Same code and settings as 2.31: see the 2.31
README, "Seihai secure login". CI logs in once more with
`--secure-login required` (`scripts/loopback.sh`).

## Not yet, or not known

- [x] ~~The Login server's scripted GUI and GS2: 140 and 197 (scripts and the
  `GRESCR01` cache) and 190~~ run in `quattro-play`'s script host
  (common/cpp/quattro, `shell/scripts`).
- [x] ~~195 (gani scripts) is accepted and ignored.~~ In `quattro-play`
  195's header lines (`SETBACKTO`, `LOOP`, `CONTINUOUS`, `SINGLEDIRECTION`)
  change a gani already shown, the newest winning; for a gani not loaded
  yet they are lost, as in the lab. A non-looping gani with a `SETBACKTO`
  falls back once it has played, and the client sends the new gani.
- [x] ~~111 (`creationtime.dat`) and 198~~: in `quattro-play` 111's body
  replaces `creationtime.dat` in the install folder byte for byte, and
  198's value is stored, as the original does.
- [ ] 109 (a file redirect to a URL) is kept but not fetched.
- [x] ~~46 (ENTERLEVEL) on level entry and 162 (the ping answer)~~:
  `quattro-play` sends 46 (`c 1`) with each level (before the first props
  when the level comes first, right after them when the server sends the
  props first) and answers 108 with 162.
- [x] ~~Level links~~: `quattro-play` follows a level link itself with
  `LEVELWARP` (0), so a server that leaves links to the client works.
- [x] ~~The base-file requests~~: with `--download-files`, `quattro-play`
  asks for `basepackage.gupd` twice after each login (23, or 47 with a
  copy cached before the run), then `arial.ttf` when no folder has it.
- [ ] The keep-alive 24 is not sent (whether 6.x sends 24 as a keep-alive
  is not settled).
- [x] ~~`GR-V1.05` levels~~ (common/cpp/quattro `files/level`).
- [ ] `GRPKG001` update packages.
- [x] ~~Nickname colours by AP~~ and the 6.x chat look: white chat with
  a blue (1, 1) shadow above the head, word-wrapped upward from 11
  characters; the nickname under the feet in its AP colour; `showap`; the
  own chat cleared after 3 s with an empty prop 12.
- [ ] The chat font itself (Tempus Sans ITC 24): drawn in the built-in
  stand-in face.
- [ ] Whether 6.03r7 plays offline at all is not traced; Training keeps 3.153's.
- [ ] No side-by-side run against the real 6.03r7; that is 0.0.2 work.
- [ ] Everything still missing from the 5.00r7 rebuild.
- [x] Provisional standalone header probe and diagnostic-only want-script
  helpers, tested independently of the client.
- [ ] CRC/cache validation, client integration and script execution.
- [x] Actual Quattro controls and level view: on Linux the game runs in
  `quattro-play` (common/cpp/quattro).
- [ ] GS2 opcode bodies and wire ids; the 6.1.1.3 connector, UDP and
  package rows are not this folder.
