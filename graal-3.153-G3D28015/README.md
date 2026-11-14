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

### On the Torque engine (Linux, Windows, macOS)

The Linux zip also holds `graal304-torque` and `libGame3153Lib.so`, the
Windows zip `graal304-torque.exe` and `Game3153Lib.dll`, and the macOS zips
`graal304-torque.app` with `libGame3153Lib.dylib` inside it. Copy them
into the root of a 3.153 install (the folder with `main.cs` and
`scripts2D/`) and start `graal304-torque`. It sees a 3.153 install and runs
its own scripts on the rebuilt Torque engine (`common/torque/guigraal`):
the main menu at 640 × 480, its logo and its text, with the game drawn
inside the `Adventure` control. The install ships no font caches, so the
fonts are made from the system's Arial, or Liberation Sans or DejaVu Sans
where there is no Arial. It also starts with `--root DIR`. Prefs go to
`~/.graal304-torque` (`%APPDATA%\graal304-torque` on Windows). On Linux it
needs an X11 display. On macOS, drag the app with the Finder into the
install. It is not signed, so the first time choose System Settings >
Privacy & Security > Open Anyway, or run
`xattr -dr com.apple.quarantine graal304-torque.app`.

### The Pascal program

Put `Graal3153` in the root of a 3.153 install and start it with no
arguments for the start screen. It finds the install's files from there,
or from `graal-assets/3.153/` and `graal-assets/common/` next to it.
It also reads the 3.04 install layout (tile sheets in `levels/tiles/`,
the offline tutorial in `levels/tutorial/`,
`levels/tiledefs/tiledefsOffline.txt`), taken to hold for 3.153 until a
3.153 install is in `graal-assets`.

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
- [ ] NPC positions still use the half-tile props. Default weapon images
  are still the older `wbowi1.gif` and `wbomb1.gif` names; the Mac lab
  asked for `wbomb1.png` and `wbowi1.png`.
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
