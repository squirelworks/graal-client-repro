# Graal 1.40 rev 1 (`GNW23090`)

The Graal 1.40 rev 1 client, rebuilt. Original: `Graal1401.ex_` from
`Graal v1.40r1.rar` (run as `Graal.exe`), 1,488,384 bytes, file date
2000-09-25, FileVersion 1.4.0.1, SHA-256 `574203dc…`. The token dates it
23 Sep 2000. 1.40 brought the new start window, the server list window
(F8), separate passwords per account and the new PK tag system
(`newfeatures14.txt`).

This folder starts as a copy of `graal-1.41r1-GNW13110`, the nearest
build with a rebuild, and is changed where 1.40 rev 1 is known to differ.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

## The token and the cipher (lab, 2026-11-13)

`GNW23090` is on no public version list (gs2lib's table goes from 1.391's
`GNW12080` to 1.41r1's `GNW13110`). It was read from two executables, this
one and the 1.40 build in `Graal v1.40.rar` (still labelled FileVersion
1.3.9.1), and is now **seen on the wire**: in the Windows 10 lab VM, with no
network, the real 1.40 rev 1 was started in "One Player Online" against a
capture server. It:

- looked up `www.graalonline.com` and connected to port **14910**, sent
  nothing, and showed the one server the capture server listed;
- on Connect, sent one frame that inflates to type 0, **a key byte**,
  `GNW23090`, the account and the password, and **no language packet**.

So 1.40 is already a **third-generation** build: the key byte that seeds
the gen-3 cipher came with 1.40, not 1.41 rev 1, and the generation-2
1.39 rev 1 (13 Aug 2000, wire-checked the same day) is the last build
without it. The rebuild, built with Free Pascal and with Delphi 7, sent the
same frame (type 0, its own random key, `GNW23090`, account, password).

## What differs from the 1.41 rev 1 rebuild

| | 1.40 rev 1 | 1.41 rev 1 |
|---|---|---|
| Token | `GNW23090` | `GNW13110` |
| Language files | next to the program (`languageEnglish.txt`, ...) | in `languages/` |
| GS1 commands | 125 | 126 (adds `showstats`) |
| Game window form | 507 px high; an editor scroll bar and one more control 4 px further right | 514 px |
| Start dialog, F1 window | the same forms | |
| Receive dispatcher | the same (0 to 41, 43, 75, 100) | |

The command counts are graal_analysis `tools/gs1-table-scan` reads
(`client-internals/graal2002-and-140-builds.md`); the rebuild does not
gate GS1 commands by version yet.

## Units

Same split as the 2.05 rev 2 rebuild, with the `205` units renamed `140r1` (by way of the 1.41 rev 1 rebuild):

| Unit | What it does |
|---|---|
| `src/Protocol140r1.pas` | ids, token, the props and messages 1.40 rev 1 reads |
| `src/GraalClient.pas` | out buffer, zlib frames, gen-3 insertion, login |
| `src/Adventure.pas` | game state, message handlers, tick, drawing |
| `src/Graal140r1.dpr` | front end: the start window with no arguments, or the command line |
| `src/StartWindow140r1.pas` | the 1.40 start window and server list (its own copy of `common/GStartScreen.pas`, because 1.40 opens on a game-mode window) |
| `src/StartScreen140r1.pas` | its listserver step and its character |
| `src/Npc140r1.pas`, `src/NpcBridge140r1.pas`, `src/Baddy140r1.pas`, `src/Sound140r1.pas`, `src/Map140r1.pas`, `src/RunMode.pas`, `src/editor/` | as in the 2.05 rev 2 rebuild |

## The listserver

The real 1.40 and 1.41 open a plain zlib link to the listserver and send nothing;
the server sends the list. Both ask `www.graalonline.com` on
port 14910, which no longer answers. This was checked in the lab on 2026-11-04: the
real exe under Wine connected to `seihai-listserver` on 14923 and sent no
byte until the list came. The public listserver's legacy port answers only
a classic login, so the rebuild sends one (id 0 `newmain`, then id 1 with
the account and password), as the 2.05 rebuild does. Default:
`listserver.graal.in`, port 14923. A `listserver.txt` next to the program
(host on the first line, port on the second) names another.

## Where it finds its files

The program sits at the top of its folder and reads only that folder:

1. the folder itself, laid out as a 1.40 install (`levels/`, `sounds/`,
   `pics1.png`, ...), or the folder given with `--data`;
2. `graal-assets/1.40r1/`;
3. `graal-assets/common/`.

Nothing found: its own built-in graphics and starter level fill in.

Files this build opens, for the assets zip:

- tiles and types: `pics1.png`, `arrays.dat`, `objects.dat`
- player: `body.png`, `sprites.png`, `levels/heads/`, `levels/swords/`,
  `levels/shields/`, `bomb1.png`, `state.png`, `letters.png`
- maps: `bigmap.txt`, `map.png`, `minimap.txt`, `map2.png`
- One Player: `levels/start1.graal`
- sounds: `sounds/bomb.wav`, `chest.wav`, `crush.wav`, `dead.wav`,
  `extra.wav`, `put.wav`

## Checks for 0.0.1

- Builds with Free Pascal on Windows; `Test140r1`, `TestEditor140r1` and
  `TestSoundMap140r1` pass with no leaks.
- Delphi 7 builds `Graal140r1` (lab VM).
- The lab wire check above, and the start windows side by side: the same
  form, language list, game modes and character list.

## Not yet (0.0.2)

- [ ] The 1.40 PK tag rules (power by alignment points), separate passwords
  per account, and the F8 server list in game.
- [ ] Everything still open in the 1.41 rev 1 rebuild: drawing from the
  sprite sheet, two to four players, save games, the F1 options window, the
  HUD and the version's own GS1 command set.
- [ ] The 1.40 build in `Graal v1.40.rar` (same token, FileVersion 1.3.9.1,
  2000-09-24): compared byte for byte with this one.
