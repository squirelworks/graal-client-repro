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

## Checks for 0.0.1

- Builds with Free Pascal on Linux and Windows; `Test21t3`,
  `TestEditor21t3` and `TestSoundMap21t3` pass.
- `scripts/loopback.sh` passes against seihai-gserver.
- Lab run under Wine (2026-11-04): the real test 3 and the rebuild each
  opened their start window, got the list from seihai-listserver and logged
  into seihai-gserver. Screenshots and the real client's login capture are
  in the project files, `graal-delphi/every-client-smoke/2.1t3/`.

## Not yet (0.0.2)

- The test 3 start window layout, with the account fields on the first page.
- The tabbed options window (General, Video, Audio, Controls).
- Anything props 43 to 45 do on screen (they are read and dropped).
- UDP message 27.
