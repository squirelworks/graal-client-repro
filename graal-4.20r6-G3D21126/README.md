# Graal 4.20r6 (`G3D21126`)

The Mac OS X 4.20r6 client, rebuilt for Linux and Windows. The original is
one PowerPC program (`Graal.app`, `CFBundleVersion` 0.6.1d1, binary built
2006-12-21, the same day as the Linux 4.206; Mach-O SHA-256
`bbda8689311bbc07aa589c1d6013a4c935646fd84362c964f5b8bb2e7cc4a3eb`),
taken from Batch-1 `Graal-4.20r6-macppc-Graal4.dmg.bz2` (Wayback capture
of graalonline.com, 2007-03-15). It logs in like the other 4.x clients:
no listserver, a game server named `Login` first, and id 178 hands it on
to a game server.

No lab run of this binary exists yet. The folder starts as a copy of the
4.11 Mac rebuild (`graal-4.11mac-G3D27076`, which was first, wrongly,
named 4.20r6), whose behaviour came from a qemu run of the 4.11 Mac
binary, and that in turn is the 4.20r8 rebuild with the Mac differences.
The Mac differences seen on the 4.11 Mac (the `mac` platform, OSTYPE and
code page, the empty 44, the 99 server ids) are taken for 4.20r6 until a
run of this binary says otherwise.
This is the 0.0.1 reproduction: hit or miss.

## Token

`G3D21126` is the token listed for the Mac 4.20r6 (Batch-1
`Web-Discovered/TOKENS.md`). It has not been read from the binary (the
x86 scans do not apply to PowerPC, and no literal is in the file) or seen
on the wire. Read as G3D + day, month and year digit it is 21 Dec 2006,
the binary's build date, as the other 4.x tokens match theirs. The Linux
4.20r6 sends `G3D22126` and the Windows 4.20r8 `G3D20126`.

## Sources

From [graal_analysis](https://github.com/squirelworks/graal_analysis), not
from decompiled code:

| Area | Notes |
|---|---|
| Token, Login server, login line, ids handled | `protocol/v4x-clients.md` |
| Profile values | `version-profiles/4.04-4.20.toml` |
| The 4.11 Mac on Mac OS X 10.4 in qemu (the notes call it 4.20r6), taken for 4.20r6 | `version-profiles/lab-mac-tiger-2026-10-31.md` |
| What 4.04r2 sends, taken where the Mac run is silent | `client-internals/live-behaviour-404.md` |
| Everything carried over | the 4.20r8, 4.04r2, 3.153 and 2.22 folder READMEs |

## What differs from the 4.20r8 rebuild

| | 4.20r8 | 4.20r6 (this folder) |
|---|---|---|
| Game token | `G3D20126` | `G3D21126` |
| Login line platform | `win` | `mac` (the hash fields are sent empty) |
| OSTYPE, code page | `wind`, 1252 (assumed) | `mac`, 0 (seen in the qemu run) |
| 44 (in the login burst and the answer to 182) | the program's name | empty, as the qemu run saw |
| Server ids handled | 101 | 99: no 41, no 196 |

The Login session, 178, the messages after login, X2/Y2 walking, 107 on
layer 0 and 108 with no answer are as in 4.20r8. The qemu run (of the 4.11
Mac) saw the same
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
then `graal-assets/4.20r8/` (the 4.20r6 Linux install ships the same
files, so the shared zip keeps one copy; the Mac install is not compared
yet), then `graal-assets/common/`, next to it.
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

- [ ] A macOS build: there is no window back end on macOS yet, and macOS is
  left out of CI and releases unless asked.
- [ ] The 24 period on a real Mac; the Mac send ids beyond what the qemu run
  saw (`pli_sent` is a lead only).
- [ ] The 3D mode (Torque protocol 21 on the Mac).
- [ ] Everything still missing from the 4.20r8 rebuild.
- [ ] No side-by-side run against the real 4.20r6; that is 0.0.2 work.
- [ ] A lab run of this binary (Tiger VM): see `G3D21126` on the wire, and
  check the platform, OSTYPE, the empty 44 and the 99 server ids, all
  taken from the 4.11 Mac run so far.
- [ ] Compare the Mac 4.20r6 install's files with 4.20r8's.
