# Graal 5.12 (`G3D14097`)

The 5.12 client, rebuilt. The original is the Windows build of October
2007, the last of the split clients: a Delphi launcher over the C++ engine
library `GraalEngine.dll` (plus `Graal3DEngine.dll` for 3D), shipped in a
MoleBox bundle. On the wire it keeps the gen-5 codec of 2.22 to 4.20 with
its own token, a fifth login field, and its own cipher step for packed
frames. This folder starts from `graal-5.00r7-G3D22067`, which has the
same receive switch, and changes what the 5.12 notes say differs. This is
the 0.0.1 reproduction: hit or miss.

It is two programs in one, as the 4.04r2 folder is:

- `Graal512 --engine`: the launcher over the rebuilt engine library
  (`common/cpp/graalengine`). The engine runs the start menus from the
  player's own 5.12 `GraalEngine.dll` on the GS2 machine, and Start logs
  in through the engine's 2D session (the Login server, the 178 hand-on,
  the level in GraalGui's playfield, walking with the arrows through the
  menus' own key bindings, the chat bar).
- `Graal512` with no `--engine`: the Pascal stand-in carried over from
  5.00r7 (start screen, server list from a Seihai listserver, login, level,
  walk), with 5.12's wire rules.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

## Sources

From [graal_analysis](https://github.com/squirelworks/graal_analysis), not
from decompiled code:

| Area | Notes |
|---|---|
| Token, login line, fifth field, short bodies compressed | `protocol/v5v6-windows-unpacked.md` |
| Cipher step for packed frames | `protocol/v5v6-lab-play.md`, "5.12's cipher step count" |
| Ids, login fields in table form | `version-profiles/5.00-6.03.toml` |
| Login mode, server warp, movement | `version-profiles/lab-v5-2026-10-30.md` |
| The launcher and engine library | `torque/5007-launcher.md`, `torque/5007-engine.md` |
| Everything carried over | `../graal-5.00r7-G3D22067/README.md` |

## What differs from the 5.00r7 rebuild

| | 5.00r7 | 5.12 (this folder) |
|---|---|---|
| Game token | `G3D22067` | `G3D14097` |
| Login line | `win` and three machine fields | then a fifth field, the quoted Windows version (`"6.2 9200 "`, what Windows 8 and later report to a program with no manifest) |
| Short bodies | raw below 0x30 bytes unless zlib is shorter | always zlib (bzip2 from 0x1000 bytes, as before) |
| Cipher, zlib and bzip2 frames | one step per 4-byte group present, rounded up | `len / 4` steps, rounded down (still at most 4); raw frames still round up |
| Server ids handled | 100 | the same 100 |
| Window title | | "G r a a l" with eight spaces spread before and after it |

The cipher step matters: a compressed frame under 16 bytes whose length is
not a multiple of 4 leaves a rounding-up peer one step behind, and every
later frame is garbage. A server has to step the same way for the 5.12
token, as a 5.12-era server did; the lab's real 5.12 plays against our
gserver that way.

## The engine library launcher (`--engine`)

```
Graal512 --engine [--engine-lib FILE] [--window] [--frames N] [--connect NAME@HOST:PORT]
```

Unlike 4.04r2, the 5.12 engine carries no `StartScript_MainMenu`: its 11
start scripts are Profiles, GraalGui, GraalGui3D, OptionsWindow,
PlayerProfile, QuitDialog, MessageBoxDialog, SetupDialog, SelectFileDialog
and the two move maps (lab read of the real 5.12 engine). The main menu
is the launcher's own window, and the client goes to the Login server as
guest (`guest` and the built-in password, `protocol/v5v6-windows-unpacked.md`),
whose scripted lists are the next screens. So with no `--connect`, the
launcher calls `openGraalServerList` (the licence's Login host), and the
engine shows GraalGui once connected. The Login server draws the level but
no characters until it sends 178, as the 5.x notes say.

Otherwise it is as 4.04r2's `--engine`, with the 5.0 launcher's slot set (95 slots: no
`LogGraalMessage`, no stretched draw) and `graalengine_setBuild("5.12")`,
which gives the engine the 5.12 wire row
(`common/cpp/quattro/net/profile.cpp`) and the 5.0 GS2 profile. The menus
come from `GRAAL_ENGINE_FILE`, else the install's own `GraalEngine.dll`.
The 5.0 launcher has no log slot, so `GRAALENGINE_LOG=1` prints the
engine's lines on stderr.

## Units

As in 5.00r7 (from 3.153), with the suffix `512`: `Protocol512`, `GraalClient`,
`Adventure`, `Graal512.dpr`, `ListServer512`, `StartScreen512`, `RunMode`.

## Running it

Put `Graal512` in the root of a 5.12 install and start it with no
arguments for the start screen. It finds the install's files from there,
or from `graal-assets/5.12/` and `graal-assets/common/` next to it.

Start asks a Seihai listserver for the server list (`listserver.txt` next
to the program, else `listserver.graal.in` on 14922), since the rebuild
cannot show the Login server's scripted list. The picked server's name
becomes the client's server name, as if the Login server had already
warped there, so the player is drawn.

```
GRAAL_PW=... Graal512 --server HOST:PORT --account NAME            # as Login
GRAAL_PW=... Graal512 --server HOST:PORT --account NAME --server-name Classic
Graal512 --level some.nw                                          # offline
```

With `--server` and no `--server-name` the server is `Login`: the level is
drawn, characters are not, until the server sends a 178.

## Files it opens

From the program's folder (or `--data`), then `graal-assets/5.12/`, then
`graal-assets/common/`. The layout is 5.00r7's, taken for 5.12 until it is
checked against a 5.12 install:

- `pics1.png` (or `pics1.gif`) at the top or in `levels/tiles/`, where a
  5.12 install keeps it; `arrays.dat` (a 5.12 install has none, so the
  built-in tile types are used)
- `levels/` for levels, ganis and images; `levels/heads/`, `levels/bodies/`,
  `levels/swords/`, `levels/shields/`, `levels/hats/`, `levels/images/`,
  `levels/tiles/` and `levels/images/downloads/` (where the install keeps
  `sprites.png`)
- `levels/offlinetutorial_b-2.nw` (or `.graal`) for Training, else `start.nw`
  (a 5.12 install has no offline tutorial, so Training plays `start.nw`)
- `listserver.txt` (optional)

## Not yet, or not known

- [x] ~~The Login server's start menus~~: with `--engine`, the install's
  own menus run and Start logs in through the engine's session
- [ ] The resources of the real 5.12 launcher (icon, start art, forms):
  not extracted yet, so the stand-in uses 5.00r7's look and the default
  icon.
- [ ] The Login server's scripted GUI (server list, accounts) and GS2 in
  general: 140 and 197 (class and weapon scripts, the `GRESCR01` cache),
  195 (gani scripts) and 190 (`onServerListerConnect`) are accepted and
  ignored by the stand-in.
- [ ] `GR-V1.05` levels (tile layers) and `GRPKG001` update packages.
- [ ] The base-file requests after the language (`basepackage.gupd` by 23,
  then 34 for `guigames_arcmessage2.png`), and fetching `sword.wav` and
  `lift.wav` from the server, as the lab saw 5.12 do.
- [ ] The "Players: N online" window 5.12 opens at login.
- [ ] `GuiShowImgCtrl` animations, offline mode's level and the weapon and
  item keys (`doA`, `doS`, `doD`) in the engine launcher.
- [ ] The 3D mode (`Graal3DEngine.dll`, protocol 24; Track C4).
- [ ] No side-by-side run against the real 5.12; that is 0.0.2 work.
