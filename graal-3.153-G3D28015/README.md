# Graal 3.153 (`G3D28015`)

The 3.153 client, rebuilt. The original is the Mac OS X (PowerPC, Carbon)
build of the Torque C++ client, February 2005. On the wire it is the
Windows 2.31 client with its own token. This folder starts from
`graal-3.04-G3D03014` and changes what the notes read from the 3.153
binary and from the Mac lab run. Where a behaviour is not in either, the
3.04 lab run is taken to hold. This is the 0.0.1 reproduction: hit or miss.

## Sources

From [graal_analysis](https://github.com/squirelworks/graal_analysis), not
from decompiled code:

| Area | Notes |
|---|---|
| Token, listserver, licence file, ids handled | `protocol/v3x-clients.md` |
| Sent ids, props, features | `version-profiles/3.04-3.153.md` and `.toml` |
| Wire behaviour taken from 3.04 | `version-profiles/lab-304-linux-2026-10-30.md` |
| Mac lab (login props, X2/Y2 walk) | `version-profiles/lab-mac-tiger-2026-10-31.md` |
| Everything carried over | `../graal-3.04-G3D03014/README.md`, `../graal-2.22-GNW03014/README.md` |

## What differs from the 3.04 rebuild

| | 3.04 | 3.153 (this folder) |
|---|---|---|
| Game token | `G3D03014` (2.22's date) | `G3D28015` (2.31's date) |
| OSTYPE prop | `linux` | `mac` |
| Server ids handled | 79 | 88: no 44; adds 67, 74, 82, 104, 131 to 134, 187, 189 |

Listserver (`G3D30123`), the licence file, the login frame, no tamper
check and no 24 over TCP are as in 3.04.

## Units

As in 3.04, with the suffix `3153`: `Protocol3153`, `GraalClient`,
`Adventure`, `Graal3153.dpr`, `ListServer3153`, `StartScreen3153`, `RunMode`.

## Running it

### Default: the Torque engine (Linux, Windows, macOS)

Put the zip's programs in the root of a 3.153 install (the folder with
`main.cs` and `scripts2D/`). With no arguments, `Graal3153` starts
`graal304-torque` next to it (the install's own scripts on the rebuilt
Torque engine: main menu at 640 × 480, server list, options, F2, game in
`Adventure`). You can also start `graal304-torque` yourself. The Linux zip
holds `graal304-torque` and `libGame3153Lib.so`; Windows
`graal304-torque.exe` and `Game3153Lib.dll`; macOS `graal304-torque.app`
with `libGame3153Lib.dylib` inside. The install ships no font caches, so
fonts are made from the system's Arial, or Liberation Sans or DejaVu Sans
where there is no Arial. Prefs go to `~/.graal304-torque`
(`%APPDATA%\graal304-torque` on Windows). On Linux it needs an X11
display. On macOS, drag the app into the install; it is not signed, so the
first time choose System Settings > Privacy & Security > Open Anyway, or
run `xattr -dr com.apple.quarantine graal304-torque.app`. `--root DIR`
still works on the Torque program.

### Pascal fallback

`Graal3153 --pascal`, or `GRAAL_PASCAL=1` / `GRAAL_PASCAL_GAME=1`, opens the
Pascal start screen instead. The same fallback applies when
`graal304-torque` is missing, or on Linux with no `DISPLAY`. CLI runs stay
in Pascal. Put `Graal3153` in the root of a 3.153 install; it finds the
install's files from there, or from `graal-assets/3.153/` and
`graal-assets/common/` next to it. It also reads the 3.04 install layout
(tile sheets in `levels/tiles/`, the offline tutorial in
`levels/tutorial/`, `levels/tiledefs/tiledefsOffline.txt`), taken to hold
for 3.153 until a 3.153 install is in `graal-assets`.

```
GRAAL_PW=... Graal3153 --server HOST:PORT --account NAME
Graal3153 --level some.nw                  # offline
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

- [ ] The ids 3.153 handles beyond 3.04 are accepted and ignored: 67 (folder
  log), 74 (RC chat), 82 (server text), 104, 131 to 134 (class and gani
  scripts), 187 and 189 (precise movement).
- [x] Walking sends X2 and Y2 (props 78 and 79), and Z2 (80) when the
  height changes. Half-tile X and Y (15 and 16) are not sent. Incoming
  X2, Y2 and Z2 are applied, for the player and for other players, and
  Z2 keeps the signed 1/16-tile height (1/16 and 1.5 stay). The
  Mac lab walk used 78 and 79
  (`version-profiles/lab-mac-tiger-2026-10-31.md`).
- [ ] What 3.153 sends beyond 3.04, still not sent: 46 ENTERLEVEL, 50, the
  RC file browser, 152/154 text, 155/156 uploads, 157/158 gani and script
  requests.
- [x] Incoming NPC props 75, 76 and 77 are stored as a fractional
  position. Z2 (prop 77) sets Z. Graal_analysis
  `protocol/player-props.md` (the NPCPROP table, repeated in
  `manual/02-protocol/06-props.md`) names 75 and 76 as X2 and Y2,
  encoded as player X2 and Y2: a short, `abs(v * 16)` shifted up one
  bit, with the sign in the low bit. Prop 77 is Z2, two bytes decoded
  the same way. Incoming 1/16 and 1.5 stay, positive and negative.
  `version-profiles/plo-npcprops-layouts.tsv` says the 2.31 NPC parser
  adds Z2 (77) and the highest id it parses is 77 (it still stops at
  48 to 52); that row gives no byte encoding.
  `version-profiles/3.04-3.153.toml` only sets `npcprops_max = 77`.
  In that profile, player prop 75 is the OS name and player prop 76 is
  the code page. The Mac lab walk records the player's props 78 and 79
  (`version-profiles/lab-mac-tiger-2026-10-31.md`).
  No note in that set says a 3.153 client sends NPC props 75 and 76
  when a script assigns `x` or `y`, or on `move`. A position this
  client changes is sent as half-tile X and Y (props 2 and 3). `move`
  (GsOpMove) marks those half-tile props at the position then; the
  existing 50 ms tick steps the NPC afterwards and adds no send.
  Half-tile X and Y are still accepted from a server.
- [x] Default weapon images are `wbomb1.png` and `wbowi1.png`. The Mac
  lab's 3.153 session sent UPDATEFILE for those names
  (`version-profiles/lab-mac-tiger-2026-10-31.md`).
- [ ] Walk props still go out every 100 ms. The Mac capture's X2 spacing
  was about 150 ms.
- [ ] The 3D mode (Torque on UDP, the listed port + 1, `Graal3D` protocol 19).
- [ ] The Mac lab captured the first props (0, 18, 31, 33, 52, 75 `mac`,
  76 = 1250). The login frame's map-file and head requests are still the
  3.04 run's. The two default weapon icons and the list icons named by
  180 are still not asked for.
- [x] The code page prop is 1250, the value in the Mac lab's first props.
- [ ] Everything still missing from the 3.04 rebuild.
- [ ] No side-by-side run against the real 3.153; that is 0.0.2 work.
