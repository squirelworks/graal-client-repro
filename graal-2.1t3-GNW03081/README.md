# Graal 2.1 test 3 (`GNW03081`)

The 2.1 test 3 client, rebuilt. Original: `Graal.exe` 2.1 test 3, 1,753,600
bytes (MD5 `2116a7ba03648dcc004035534ec94de8`, linked 2001-09-27,
FileVersion 2.1.0.0), Delphi with DelphiX and zlib. It is a public test of
2.1 with new tiles and a new start window. It still sends 2.05's token, so a
game server cannot tell it from 2.05.

This folder starts as a copy of `graal-2.05r2-GNW03081` and is changed where
the version notes (graal_analysis `version-profiles/141-217.md`, "2.1 test
2 / test 3") say test 3 differs. Version 0.0.1 carries the differences a
server or a player sees first; the rest is listed under "Not yet".

## What differs from the 2.05 rev 2 rebuild

| | 2.1 test 3 | 2.05 rev 2 |
|---|---|---|
| Token | `GNW03081` (the same) | `GNW03081` |
| Listserver login | id 0 `newmain`, then id 1 account and password | id 0 `newmain` only (the rebuild sends id 1 too) |
| Built-in listserver port | 14922 | 14921 |
| Player props read | own 0 to 45; others add 43 to 45 | own 0 to 42 |
| Server messages known | adds 49 and 169 | |
| Start window | account and password on the start window, then the list | account and password on the list |

The game login is the same as 2.05: the login line, LANGUAGE (37), the
default-image file requests, then props 0, 11, 13, 18, 31 and 33 (lab,
2026-11-04).

## The listserver

Default: `listserver.graal.in`, port 14923. Test 3's own port was 14922, but
the public listserver answers this classic login only on its legacy port,
14923. A `listserver.txt` next to the program (host on the first line, port
on the second) names another.

## Where it finds its files

The program sits at the top of its folder and reads only that folder:

1. the folder itself, laid out as an install (`levels/`, `pics1.png`, ...),
   or the folder given with `--data`;
2. `graal-assets/2.1t3/`, then `graal-assets/2.05r2/`;
3. `graal-assets/common/`.

Nothing found: its own built-in graphics and starter level fill in.

Files this build opens beyond the 2.05 rev 2 set, for the assets zip: test 3's
own `arrays.dat`, `state.png`, `maps/newmainmap.png` and
`maps/newmainmap2.png`, and its `levels/npcs/`, `levels/smilies/` and
`levels/webgifs/`. The test 3 archive ships no `pics1.png`, ganis, heads or
bodies, so those come from the 2.05 rev 2 set.

## Install files from another version

`src/res/Graal21t3Install.res` and `src/res/install-manifest.txt` carry 127 files that the 2.1t3 install does not have. Every one has the same bytes as the file at the same path in the **nm26** install (`graal clients.zip`, `graalnm26/`). Some of them also match older installs (1.28b2 to 1.41r1, 2.05 rev 2). They are stand-ins: the 2.1t3 install in the project files lacks them, and nothing in this folder said so until now. `state.png` replaces the 2.1t3 install's own copy. By folder: `levels/ganis/` 51, `levels/heads/` 33, `levels/tutorial/` 17, top level 10, `sounds/` 9, `levels/weather/` 6, `levels/` 1. Checked on 2026-11-12 by CRC32 against every install in the project files.

<details><summary>The 127 files</summary>

- `body.png`
- `body2.png`
- `body3.png`
- `body4.png`
- `bomb1.png`
- `bomb2.png`
- `letters.png`
- `levels/ganis/bomy_attack.gani`
- `levels/ganis/bomy_birce0.png`
- `levels/ganis/bomy_blindo0.png`
- `levels/ganis/bomy_draktha0.png`
- `levels/ganis/bomy_duck.gani`
- `levels/ganis/bomy_hide.gani`
- `levels/ganis/bomy_idle.gani`
- `levels/ganis/bomy_kick.gani`
- `levels/ganis/bomy_kiro0.png`
- `levels/ganis/bomy_naifets0.png`
- `levels/ganis/bomy_nero0.png`
- `levels/ganis/bomy_sit.gani`
- `levels/ganis/bomy_vadakar0.png`
- `levels/ganis/bomy_visio0.png`
- `levels/ganis/bomy_walk.gani`
- `levels/ganis/bomy_xen0.png`
- `levels/ganis/carried.gani`
- `levels/ganis/carry.gani`
- `levels/ganis/carrypeople.gani`
- `levels/ganis/carrystill.gani`
- `levels/ganis/dead.gani`
- `levels/ganis/def.gani`
- `levels/ganis/glare1.gif`
- `levels/ganis/grab.gani`
- `levels/ganis/gralats.gani`
- `levels/ganis/hidden.gani`
- `levels/ganis/hiddenstill.gani`
- `levels/ganis/hurt.gani`
- `levels/ganis/idle.gani`
- `levels/ganis/kick.gani`
- `levels/ganis/lava.gani`
- `levels/ganis/lift.gani`
- `levels/ganis/pull.gani`
- `levels/ganis/push.gani`
- `levels/ganis/ride.gani`
- `levels/ganis/rideeat.gani`
- `levels/ganis/ridefire.gani`
- `levels/ganis/ridehurt.gani`
- `levels/ganis/ridestill.gani`
- `levels/ganis/ridesword.gani`
- `levels/ganis/shoot.gani`
- `levels/ganis/sit.gani`
- `levels/ganis/skip.gani`
- `levels/ganis/skip.png`
- `levels/ganis/skip_icon.png`
- `levels/ganis/sleep.gani`
- `levels/ganis/spin.gani`
- `levels/ganis/swim.gani`
- `levels/ganis/sword.gani`
- `levels/ganis/walk.gani`
- `levels/ganis/walkslow.gani`
- `levels/heads/head0.gif`
- `levels/heads/head1.gif`
- `levels/heads/head10.gif`
- `levels/heads/head11.gif`
- `levels/heads/head12.gif`
- `levels/heads/head13.gif`
- `levels/heads/head14.gif`
- `levels/heads/head15.gif`
- `levels/heads/head16.gif`
- `levels/heads/head17.gif`
- `levels/heads/head18.gif`
- `levels/heads/head19.gif`
- `levels/heads/head2.gif`
- `levels/heads/head20.gif`
- `levels/heads/head21.gif`
- `levels/heads/head22.gif`
- `levels/heads/head23.gif`
- `levels/heads/head24.gif`
- `levels/heads/head25.gif`
- `levels/heads/head26.gif`
- `levels/heads/head27.gif`
- `levels/heads/head28.gif`
- `levels/heads/head29.gif`
- `levels/heads/head3.gif`
- `levels/heads/head4.gif`
- `levels/heads/head5.gif`
- `levels/heads/head6.gif`
- `levels/heads/head7.gif`
- `levels/heads/head8.gif`
- `levels/heads/head814.gif`
- `levels/heads/head9.gif`
- `levels/heads/headcheater.gif`
- `levels/heads/sleepkoji.gif`
- `levels/tutorial/tutorial_a-1.graal`
- `levels/tutorial/tutorial_a-2.graal`
- `levels/tutorial/tutorial_a-3.graal`
- `levels/tutorial/tutorial_a-4.graal`
- `levels/tutorial/tutorial_b-1.graal`
- `levels/tutorial/tutorial_b-2.graal`
- `levels/tutorial/tutorial_b-2_house.graal`
- `levels/tutorial/tutorial_b-3.graal`
- `levels/tutorial/tutorial_b-4.graal`
- `levels/tutorial/tutorial_c-1.graal`
- `levels/tutorial/tutorial_c-2.graal`
- `levels/tutorial/tutorial_c-3.graal`
- `levels/tutorial/tutorial_c-4.graal`
- `levels/tutorial/tutorial_housegate.png`
- `levels/tutorial/tutorialmap.png`
- `levels/tutorial/tutorialmap.txt`
- `levels/tutorial/tutorialmap2.png`
- `levels/weather/arrayclouds.graal`
- `levels/weather/arrayrain.graal`
- `levels/weather/arraysnow.graal`
- `levels/weather/cloud.gif`
- `levels/weather/raindrop.gif`
- `levels/weather/snow.gif`
- `levels/worldu-13.nw`
- `pics1.png`
- `sounds/bomyload.wav`
- `sounds/bomyload0.wav`
- `sounds/bomyload1.wav`
- `sounds/bomyload2.wav`
- `sounds/bomyload3.wav`
- `sounds/bomyload4.wav`
- `sounds/bomywalk0.wav`
- `sounds/bomywalk1.wav`
- `sounds/bomywalk2.wav`
- `sprites.png`
- `state.png`

</details>

## Checks for 0.0.1

- Builds with Free Pascal on Linux and Windows; `Test21t3`,
  `TestEditor21t3` and `TestSoundMap21t3` pass.
- `scripts/loopback.sh` passes against seihai-gserver.
- Lab run under Wine (2026-11-04): the real test 3 and the rebuild each
  opened their start window, got the list from seihai-listserver and logged
  into seihai-gserver. Screenshots and the real client's login capture are
  in the project files, `graal-delphi/every-client-smoke/2.1t3/`.

## Not yet (0.0.2)

- [ ] The test 3 start window layout, with the account fields on the first page.
- [ ] The tabbed options window (General, Video, Audio, Controls).
- [ ] Anything props 43 to 45 do on screen (they are read and dropped).
- [ ] UDP message 27.
