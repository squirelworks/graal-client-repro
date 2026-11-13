# Graal 4.11 Mac (`G3D27076`)

The Mac OS X 4.11 client, rebuilt for Linux and Windows. The original is
one PowerPC program (`Graal.app`, binary built 2006-09-19, Mach-O SHA-256
`304a4d480a63cbaf70822cca56066284f392973bf9e00f3192551bff4b540f92`) built
from the same engine source as the Windows 4.x clients. It logs in the
same way: no listserver, a game server named `Login` first, and id 178
hands it on to a game server. This folder is the 4.20r8 rebuild
(`graal-4.20r8-G3D20126`) with what the notes and the qemu lab run read
from this Mac binary. This is the 0.0.1 reproduction: hit or miss.

## Why 4.11 and not 4.20r6

This folder was first named 4.20r6, because the archive copy it was built
from (`Clients-MacOS/v4/Graal v4.20r6[Mac OS X]`) carries that label. The
label is wrong:

- The same binary is the `Graal4.dmg.bz2` that graalonline.com offered in
  November 2006, when 4.11 was the current version.
- The binary was built on 2006-09-19, three days after the Linux 4.11
  (2006-09-16), and its token `G3D27076` dates it 27 July 2006, in the
  4.1x era. Linux 4.10r2 and 4.11 share one token (`G3D28076`) in the same
  way.
- The real Mac 4.20r6 is a different binary (built 2006-12-21, the same
  day as the Linux 4.206, Mach-O SHA-256 `bbda8689…`). Its listed token is
  `G3D21126`, and it gets its own folder, `graal-4.20r6-G3D21126`.

The Mac 4.10r2 (built 2006-08-22) is listed with the same token
`G3D27076`, so a server cannot tell the two Mac builds apart by token.

## Sources

From [graal_analysis](https://github.com/squirelworks/graal_analysis), not
from decompiled code:

| Area | Notes |
|---|---|
| Token, Login server, login line, ids handled | `protocol/v4x-clients.md` |
| Profile values | `version-profiles/4.04-4.20.toml` |
| This Mac binary on Mac OS X 10.4 in qemu (the notes call it 4.20r6) | `version-profiles/lab-mac-tiger-2026-10-31.md` |
| What 4.04r2 sends, taken where the Mac run is silent | `client-internals/live-behaviour-404.md` |
| Everything carried over | the 4.20r8, 4.04r2, 3.153 and 2.22 folder READMEs |

## What differs from the 4.20r8 rebuild

| | 4.20r8 | 4.11 Mac (this folder) |
|---|---|---|
| Game token | `G3D20126` | `G3D27076` |
| Login line platform | `win` | `mac` (the hash fields are fixed made-up hashes of SquirrelBook and SquirrelFS strings) |
| OSTYPE, code page | `wind`, 1252 (assumed) | `mac`, 0 (seen in the qemu run) |
| 44 (in the login burst and the answer to 182) | the program's name | empty, as the qemu run saw |
| Server ids handled | 101 | 99: no 41, no 196 |

The Login session, 178, the messages after login, X2/Y2 walking, 107 on
layer 0 and 108 with no answer are as in 4.20r8. The qemu run saw the same
kinds of message as 4.04r2; their order and timings were measured on
4.04r2 only. 24 is sent every 5.145 s as on 4.04r2: the qemu run saw 16 to
19 s, but on an emulated PowerPC that runs far slower than a real Mac.

## Units

As in 4.20r8, with the suffix `411mac`: `Protocol411mac`, `GraalClient`,
`Adventure`, `Graal411mac.dpr`, `ListServer411mac`, `StartScreen411mac`,
`RunMode`.

## Running it

Put `Graal411mac` in the root of a 4.11 Mac install (the files inside
`Graal.app`, `license/`, `levels/` and `sounds/`, copied to a Linux or
Windows folder) and start it with no arguments for the start screen. It
finds the install's files from there, or from `graal-assets/4.11mac/`,
then `graal-assets/4.20r8/` (standing in until the 4.11 Mac install is
compared with it), then `graal-assets/common/`, next to it.
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
GRAAL_PW=... Graal411mac --server HOST:PORT --account NAME
GRAAL_PW=... Graal411mac --server HOST:14900 --account NAME --server-name Login
Graal411mac --level some.nw                  # offline
```

## Seihai secure login (not in the original)

Off by default, so the login is byte for byte the original's. With
`--secure-login auto` or `required` (or one word in `secure_login.txt` in
the shared settings folder), the account, the password and the platform fields after it go sealed to
a Seihai game server or list server (version token `SEI00001`,
graal-client-repro #148). Same code and settings as 2.31: see the 2.31
README, "Seihai secure login". CI logs in once more with
`--secure-login required` (`scripts/loopback.sh`).

## Not yet, or not known

- [ ] A macOS build: there is no window back end on macOS yet, and macOS is
  left out of CI and releases unless asked.
- [ ] The 24 period on a real Mac; the Mac send ids beyond what the qemu run
  saw (`pli_sent` is a lead only).
- [ ] The 3D mode (Torque protocol 21 on the Mac).
- [ ] Everything still missing from the 4.20r8 rebuild.
- [ ] No side-by-side run against the real 4.11 Mac; that is 0.0.2 work.
- [ ] Compare the 4.11 Mac install's files with 4.20r8's (Batch-1 `Graal-4.11-macppc-Graal4.dmg.bz2`).
