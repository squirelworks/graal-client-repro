# Graal 3.04 for Linux (`G3D03014`)

The 3.04 Linux client (3.04 revision 1, "3.041"), rebuilt. The original is
a C++ program on the Torque game engine, built in January 2004, not a
Delphi program. On the wire it is the Windows 2.22 client with its own
token: the same gen-5 login, cipher, framing and compression. So this
folder starts from `graal-2.22-GNW03014` and changes only what the notes
say 3.04 does differently. This is the 0.0.1 reproduction: hit or miss,
the lab run is the yardstick.

## Sources

Everything here is written from notes in
[graal_analysis](https://github.com/squirelworks/graal_analysis), not from
decompiled code:

| Area | Notes |
|---|---|
| What 3.04 is, tokens, listserver, licence file, ids handled | `protocol/v3x-clients.md` |
| Sent ids, props, login frame, features | `version-profiles/3.04-3.153.md` and `.toml` |
| What the real client did on the wire | `version-profiles/lab-304-linux-2026-10-30.md` |
| Everything carried over from 2.22 | see `../graal-2.22-GNW03014/README.md` |

## What differs from the 2.22 rebuild

| | 2.22 | 3.04 (this folder) |
|---|---|---|
| Game token | `GNW03014` | `G3D03014` |
| Listserver | id 7 `GNW30123newmain` in a plain frame, then id 1 in gen 5 | id 7 `G3D30123newmain` and id 1 together in one plain zlib frame |
| Listserver hosts | `arrays2.dat` | `listserver.graal.in:14922` first, always; then the hosts of `license/license.graal` (lines 0, 5 and 6) |
| Login frame | 5 alone, then 37 + 39 in gen 5 | 5, 37, 34 `bigmap.txt`, 34 `minimap.txt`, all in the plain login frame |
| Tamper check (39) | at login, after every warp and gmap crossing | never |
| 24 every 5.1 s over TCP | with another player in the level | never (3.04 sends it to players over UDP) |
| First props | 0, 11, 13, 18, 31, 33, 52, 75 `wind`, 76 1252, after 34 for four list icons | 0, 18, 31, 33, 52, 75 `linux`, 76 1250, then 34 for the head |
| Server ids handled | 80 | 79: no 170, 177, 182, 183; adds 84 |

## Units

| Unit | What it does |
|---|---|
| `src/Protocol304.pas` | ids, tokens, gen-5 constants, the 79 handled ids |
| `src/GraalClient.pas` | the gen-5 link and the 3.04 login frame |
| `src/Adventure.pas` | game state, level cache, gmaps, handlers, the 50 ms tick, drawing |
| `src/Graal304.dpr` | front end: the start screen with no arguments; flags for the window, scripted keys, frame dump, stress runs |
| `src/ListServer304.pas` | the 3.04 listserver step and `license.graal` |
| `src/StartScreen304.pas` | what 3.04 plugs into the shared start screen |
| `src/RunMode.pas` | stress-run support (as 2.22's) |
| `src/TorqueNames304.pas` | a name table of GuiGraalCtrl methods, draw types, and module names. Not the engine host. The engine host is the C++ / TorqueScript work, not this unit |
| `common/torque/host304` | C++ boot: reads `manifests/3.04.list`, registers the 3.04 controls, opens the level view from one TorqueScript, moves a camera, stubs GuiGraalCtrl, sends the folder's login-shaped first frame to loopback |

## Running it

### On the Torque engine (Linux, Windows, macOS)

The Linux zip also holds `graal304-torque` and `libGame304Lib.so`; the
Windows zip holds `graal304-torque.exe` and `Game304Lib.dll`. Copy both
into the root of a 3.04 install (beside `main.cs`) and start
`graal304-torque`. The macOS zips hold `graal304-torque.app`, with the
game library inside it: drag the app with the Finder into the root of
the install and open it. It is not signed, so the first time macOS
blocks it: choose System Settings > Privacy & Security > Open Anyway
(macOS 15 has no Control-click Open), or run
`xattr -dr com.apple.quarantine graal304-torque.app`. It runs the install's own scripts on the rebuilt
Torque engine (`common/torque/guigraal`): the install's main menu, server
list, options and F2 console, with the game below drawn inside the
`Adventure` control. It also starts from the install folder as the current
folder, or with `--root DIR`. Prefs go to `~/.graal304-torque`
(`%APPDATA%\graal304-torque` on Windows). On Linux it needs an X11
display.

### The Pascal program

Put `Graal304` in the root of a 3.04 install (where the original
`graalexe` lies) and start it with no arguments for the start screen. It
finds the install's files from there, or from `graal-assets/3.04/` and
`graal-assets/common/` next to it.

It reads the 3.04 install's own layout: tile sheets in `levels/tiles/`
(`pics1.png`, `picso.png`), the offline tutorial in `levels/tutorial/`,
`levels/tiledefs/tiledefsOffline.txt` (which gives the tutorial levels the
`picso.png` sheet), and `license/license.graal`.

Walking follows 3.04's own rule, which depends on the sheet type that the
tiledef gives the level (Graal_analysis `torque/304-tile-types.md`).
On `pics1.png` (type 0, every online level unless a tiledef says
otherwise), a tile is free only when it is in `arrays.dat` array 0 or 1.
3.04 has these lists built in rather than in a file. They are 2.22's
`arrays.dat` without water tiles 1824 and 1825. 3.04 ships no `arrays.dat`, so put
2.22's in the 3.04 folder or in `graal-assets/3.04/`. Without it the
rebuild's stand-in table is used, and real levels' grass is a wall. The
offline tutorial's `picso.png` (type 1) uses 3.04's row rule and needs no
file.

```
GRAAL_PW=... Graal304 --server HOST:PORT --account NAME
Graal304 --level some.nw                  # offline
scripts/build.sh graal-3.04-G3D03014 && common/torque/host304/build/host304 --port 14802
Graal304 --server HOST:PORT --account NAME --headless --seconds 600 \
  --walk random --link-every 5 --stats-every 10   # stress run
```

## Seihai secure login (not in the original)

Off by default, so the login is byte for byte the original's. With
`--secure-login auto` or `required` (or one word in `secure_login.txt` in
the shared settings folder), the account, the password go sealed to
a Seihai game server or list server (version token `SEI00001`,
graal-client-repro #148). Same code and settings as 2.31: see the 2.31
README, "Seihai secure login". CI logs in once more with
`--secure-login required` (`scripts/loopback.sh`).

## Not yet, or not known

- [ ] The server name prefixes `P `, `3 `, `H `, `U ` pick the list tab in 3.04
  (Gold, 3D, Hosted, hidden); the shared start screen shows one list.
- [ ] The two default weapon icons (34) and the list icons (23, asked for by
  name after 180) of the first frame; only the head is asked for.
- [ ] The UDP channel between players (movement, chat, trigger actions, the
  5.1 s message), so `UDPPORT` is sent as 0.
- [ ] `GSERVL01` text levels and `GR-V1.04` heights; the licence file's RSA
  signature; the `GWEBL001` level cache.
- [ ] Everything still missing from the 2.22 rebuild: NPCs, baddies, items,
  weapons, GS1, chat bubbles, Options.
- [ ] Which offline tutorial level the Tutorial button opens, and where: the
  rebuild opens `levels/tutorial/offlinetutorial_b-2.graal` at (30, 30),
  else its starter level.
- [ ] No side-by-side run against the real 3.04 yet; that is 0.0.2 work.
- [x] A C++ host boots the nine TGE 1.2 modules, registers the 3.04
  controls, runs one TorqueScript that opens the GuiGraalCtrl level view
  and moves a camera, and stubs GuiGraalCtrl (`common/torque/host304`).
- [ ] The install's `main.cs` is not executed. The script runner is a
  line runner, and frames after the login frame are not built.
  `TorqueNames304` is a name table. This folder does not boot through it.
