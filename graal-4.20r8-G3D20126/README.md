# Graal 4.20r8 (`G3D20126`)

The 4.20r8 Windows client, rebuilt. The original (December 2006) is a
Delphi launcher over a C++ engine DLL, as 4.04r2. It logs in the same way:
no listserver, a game server named `Login` first, and id 178 hands it on
to a game server. This folder is the 4.04r2 rebuild
(`graal-4.04r2-G3D17026`) with what the notes read from the 4.20r8 engine.
This is the 0.0.1 reproduction: hit or miss.

The only 4.20r8 engine that survives is a third-party packet-logger copy
with its signature check patched out. The notes are read from that copy;
the lab ran it with the eight hooked bytes put back. Nothing here copies
from it.

## Sources

From [graal_analysis](https://github.com/squirelworks/graal_analysis), not
from decompiled code:

| Area | Notes |
|---|---|
| Token, Login server, login line, ids handled | `protocol/v4x-clients.md` |
| Profile values | `version-profiles/4.04-4.20.toml` |
| What the real client sends (the 4.20r8 runs, and the 4.04r2 ones taken to hold) | `client-internals/live-behaviour-404.md` |
| Everything carried over | the 4.04r2, 3.153 and 2.22 folder READMEs |

## What differs from the 4.04r2 rebuild

| | 4.04r2 | 4.20r8 (this folder) |
|---|---|---|
| Game token | `G3D17026` | `G3D20126` |
| Server ids handled | 98 | 101: adds 107, 108, 196 |
| 107 (board change on a layer) | not handled | layer 0 changes the board; other layers are read and dropped |
| 108 | not handled | accepted; subtype 0 would be answered with 162, whose value is not in the notes, so no answer is sent |
| 196 | not handled | read and dropped, as the real client does |

The login line (`win` and three machine fields, sent empty), the Login
session, 178, the messages after login, X2/Y2 walking and 24 every
5.145 s are as in 4.04r2. The second lab run saw 4.20r8 send the same
messages as 4.04r2; the frame order and the 24 period were timed on
4.04r2 only.

Choices made for players' privacy, where the real client sends more: the
machine fields are empty, and the answer to 182 names only the program.

## Units

As in 4.04r2, with the suffix `420`: `Protocol420`, `GraalClient`,
`Adventure`, `Graal420.dpr`, `ListServer420`, `StartScreen420`, `RunMode`.

## Running it

Put `Graal420` in the root of a 4.20r8 install and start it with no
arguments for the start screen. It finds the install's files from there,
or from `graal-assets/4.20r8/` and `graal-assets/common/` next to it. It
reads the 4.x install layout: tile sheets (`pics1.png`, `picso.png`) in
`levels/tiles/`, the offline tutorial in `levels/tutorial/` (Training
opens `offlinetutorial_b-2.graal` there), and a
`levels/tiledefs/tiledefsOffline.txt` if one is dropped in.

Start always asks `listserver.graal.in` on 14922 for a list first (a
`listserver.txt` next to the program names another). When the install has
`license/license.graal`, its Login host and fallbacks are added after the
list as extra rows named `Login`; picking one logs in there as the real
client does. They are never the default.

```
GRAAL_PW=... Graal420 --server HOST:PORT --account NAME
GRAAL_PW=... Graal420 --server HOST:14900 --account NAME --server-name Login
Graal420 --level some.nw                  # offline
```

## Engine host

`common/torque/host4208` is a C++ program for the residual Torque surface
in the 4.2.0.8 engine DLL (`GuiCanvas`, `GuiControl`, `Point2I`,
`GBitmap`, and the `GuiGraalCtrl` names). The engine has no Torque
console. That program is not this Delphi launcher, and it does not run
TorqueScript. The login token it sends is `G3D20126`, the documented Windows 4.20r8 token.

## Not yet, or not known

- [ ] Board layers other than 0 (no `GR-V1.05` file format yet either).
- [ ] The 108 answer value; the separate network thread; per-account saved
  passwords (`<account>_pass`).
- [ ] Everything still missing from the 4.04r2 rebuild: the scripted server
  list, update packages, the GUI texts after login, the 3D plug-in.
- [ ] No side-by-side run against the real 4.20r8; that is 0.0.2 work.
