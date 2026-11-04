# Graal 4.04r2 (`G3D17026`)

The 4.04r2 Windows client, rebuilt. The original (February 2006) is a
Delphi launcher over a C++ engine DLL. On the wire it is gen 5, as 2.22 to
3.153, but it has no listserver: it logs in to a game server it names
`Login`, which hands it on to a game server with id 178. This folder
starts from `graal-3.153-G3D28015` and changes what the notes and the lab
runs of the real 4.04r2 show. This is the 0.0.1 reproduction: hit or miss.

## Sources

From [graal_analysis](https://github.com/squirelworks/graal_analysis), not
from decompiled code:

| Area | Notes |
|---|---|
| Token, Login server, licence file, login line, ids handled | `protocol/v4x-clients.md` |
| Profile values | `version-profiles/4.04-4.20.toml` |
| What the real client sends (after login, walking, 24, 178) | `client-internals/live-behaviour-404.md` |
| Everything carried over | `../graal-3.153-G3D28015/README.md`, `../graal-2.22-GNW03014/README.md` |

## What differs from the 3.153 rebuild

| | 3.153 | 4.04r2 (this folder) |
|---|---|---|
| Game token | `G3D28015` | `G3D17026` |
| First server | listserver, `G3D30123` hello | a game server named `Login`, from `license/license.graal`; the rebuild asks `listserver.graal.in:14922` first and offers the Login hosts as extra rows |
| Login line | ends at the password | adds `win` and three machine fields (sent empty) |
| After the login line | 37, 34 bigmap, 34 minimap in the same frame | its own frame, then 37 and 23 `basepackage.gupd` |
| After the login burst | props, 34 for the head | 23 `idle.gani` and 157, 46, 44, props, 24, 34 `pics1.png` |
| Walking | X / Y every 100 ms | GANI and SPRITE on the first step, then X2 / Y2 every 50 ms tick, only the axes that moved |
| 24 over TCP | none | `9` every 5.145 s |
| Server ids handled | 88 | 98: adds 105, 106, 170, 182, 183, 190, 191, 193 to 195 |
| OSTYPE, code page | `mac`, 1250 | `wind`, 1252 (2.22's Windows values, assumed) |

Choices made for players' privacy, where the real client sends more:

- The three machine fields of the login line (hashes of the Windows
  product id, the MAC address and the `C:` serial) are sent empty.
- The answer to 182 (44) names only the program, not every open window.
- 183 (is this window open?) gets no answer; the answer id is not in the
  notes.

## The Login session

While the server's name starts with `login` (any case) no players are
drawn: the level is a backdrop, as in the real client. 178
`x,name,host,port`, split on commas only, closes the session and logs in
to that host under that name. Fewer than four fields are ignored.

## Units

As in 3.153, with the suffix `404`: `Protocol404`, `GraalClient`,
`Adventure`, `Graal404.dpr`, `ListServer404`, `StartScreen404`, `RunMode`.

## Running it

Put `Graal404` in the root of a 4.04r2 install and start it with no
arguments for the start screen. It finds the install's files from there,
or from `graal-assets/4.04r2/` and `graal-assets/common/` next to it. It
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
GRAAL_PW=... Graal404 --server HOST:PORT --account NAME
GRAAL_PW=... Graal404 --server HOST:14900 --account NAME --server-name Login
Graal404 --level some.nw                  # offline
```

## Not yet, or not known

- The server list and account screens as the real client shows them
  (scripted GUI from the Login server).
- Update packages (`GRPKG001`): `basepackage.gupd` is asked for, not
  saved, and C→S 47 for a cached copy is not sent.
- The ids handled beyond 3.153 are accepted and ignored except 178, 182
  and 183: 105/106 (update packages), 170 (ghost mode), 190, 191 (projectile),
  193 to 195.
- The four GUI texts after login (152 `pmguilds`, `pmservers`; 154 lister
  options), head and weapon image checks, the large-packet length (50).
- The 3D plug-in (`Graal3DEngine.dll`, Torque on UDP, protocol 19).
- Saved passwords (DES, keyed on the machine).
- Everything still missing from the 3.153 rebuild.
- No side-by-side run against the real 4.04r2; that is 0.0.2 work.
