# Graal 4.20r6 (`G3D27076`)

The Mac OS X 4.20r6 client, rebuilt for Linux and Windows. The original
(September 2006) is one PowerPC program built from the same engine source
as the Windows 4.x clients. It logs in the same way: no listserver, a game
server named `Login` first, and id 178 hands it on to a game server. This
folder is the 4.20r8 rebuild (`graal-4.20r8-G3D20126`) with what the notes
and the qemu lab run read from the Mac 4.20r6. This is the 0.0.1
reproduction: hit or miss.

## Sources

From [graal_analysis](https://github.com/squirelworks/graal_analysis), not
from decompiled code:

| Area | Notes |
|---|---|
| Token, Login server, login line, ids handled | `protocol/v4x-clients.md` |
| Profile values | `version-profiles/4.04-4.20.toml` |
| The real 4.20r6 on Mac OS X 10.4 in qemu | `version-profiles/lab-mac-tiger-2026-10-31.md` |
| What 4.04r2 sends, taken where the Mac run is silent | `client-internals/live-behaviour-404.md` |
| Everything carried over | the 4.20r8, 4.04r2, 3.153 and 2.22 folder READMEs |

## What differs from the 4.20r8 rebuild

| | 4.20r8 | 4.20r6 (this folder) |
|---|---|---|
| Game token | `G3D20126` | `G3D27076` |
| Login line platform | `win` | `mac` (the hash fields are sent empty) |
| OSTYPE, code page | `wind`, 1252 (assumed) | `mac`, 0 (seen in the qemu run) |
| 44 (in the login burst and the answer to 182) | the program's name | empty, as the qemu run saw |
| Server ids handled | 101 | 99: no 41, no 196 |

The Login session, 178, the messages after login, X2/Y2 walking, 107 on
layer 0 and 108 with no answer are as in 4.20r8. The qemu run saw the same
kinds of message as 4.04r2; their order and timings were measured on
4.04r2 only. 24 is sent every 5.145 s as on 4.04r2: the qemu run saw 16 to
19 s, but on an emulated PowerPC that runs far slower than a real Mac.

## Units

As in 4.20r8, with the suffix `420r6`: `Protocol420r6`, `GraalClient`,
`Adventure`, `Graal420r6.dpr`, `ListServer420r6`, `StartScreen420r6`,
`RunMode`.

## Running it

Put `Graal420r6` in the root of a 4.20r6 install (the files inside
`Graal.app`, `license/`, `levels/` and `sounds/`, copied to a Linux or
Windows folder) and start it with no arguments for the start screen. It
finds the install's files from there, or from `graal-assets/4.20r6/`,
then `graal-assets/4.20r8/` (the two installs ship the same files, so
the shared zip keeps one copy), then `graal-assets/common/`, next to it.
It reads the 4.x install layout: tile sheets (`pics1.png`, `picso.png`)
in `levels/tiles/`, the offline tutorial in `levels/tutorial/` (Training
opens `offlinetutorial_b-2.graal` there), and a
`levels/tiledefs/tiledefsOffline.txt` if one is dropped in.

Start always asks `listserver.graal.in` on 14922 for a list first (a
`listserver.txt` next to the program names another). When the install has
`license/license.graal`, its Login host and fallbacks are added after the
list as extra rows named `Login`; picking one logs in there as the real
client does. They are never the default.

```
GRAAL_PW=... Graal420r6 --server HOST:PORT --account NAME
GRAAL_PW=... Graal420r6 --server HOST:14900 --account NAME --server-name Login
Graal420r6 --level some.nw                  # offline
```

## Not yet, or not known

- A macOS build: there is no window back end on macOS yet, and macOS is
  left out of CI and releases unless asked.
- The 24 period on a real Mac; the Mac send ids beyond what the qemu run
  saw (`pli_sent` is a lead only).
- The 3D mode (Torque protocol 21 on the Mac).
- Everything still missing from the 4.20r8 rebuild.
- No side-by-side run against the real 4.20r6; that is 0.0.2 work.
