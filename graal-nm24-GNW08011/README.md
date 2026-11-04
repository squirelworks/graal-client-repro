# Graal NewMain 24 (`GNW08011`)

The NewMain 24 client, rebuilt. Original: `Graal-NewMain24.exe`,
1,783,296 bytes (CRC32 `08A8959E`, MD5 `229f05de7a43b98e223d8e1b58bffc63`, FileVersion 1.4.1.1), Delphi with
DelphiX and zlib. NewMain was the client for the NewMain test world of early
2001, on the 1.42 line before 2.0. NewMain 24 and NewMain 26 both send the
token `GNW08011`, which seihai-gserver reads as 1.42.

This folder starts as a copy of `graal-2.05r2-GNW03081`. It is changed where
the version notes (graal_analysis `version-profiles/141-217.md`) and the lab
runs say NewMain differs. Version 0.0.1 carries the differences a server or a
player sees first. The rest is listed under "Not yet".

## What differs from the 2.05 rev 2 rebuild

| | NewMain 24 | 2.05 rev 2 |
|---|---|---|
| Token | `GNW08011` | `GNW03081` |
| After the login line | no LANGUAGE packet | LANGUAGE `English` |
| Player props read | 0 to 36; a higher id ends the stream | own 0 to 42, others to 51 |
| Server messages handled | 0 to 45, 75, 100 to 102, 150, 151, 153; the rest are dropped | all 2.05 ids |

The listserver list (`newmain`), the tile sheet, the built-in sword, bow,
bombs and baddies, and the start window with Training are as in 2.05.

The game login was checked on the real exe in the Wine lab (2026-11-04). It
asks the listserver on port 14921 for the `newmain` list with id 0 only. In
the game it sends the login line with no LANGUAGE, asks for `sword1.png`,
`shield1.png` and `head0.png` (WANTFILE) and `body.png` (UPDATEFILE),
then sends its login props with the head by name.
seihai-gserver logged it in as `GNW08011 1.42`. The rebuild sends the login
line and the login props. The file requests are left for 0.0.2.

## The listserver

Default: `listserver.graal.in`, port 14923. The rebuild asks for the
`newmain` list with id 0, then sends id 1 with the account and password, the
classic login the public legacy port answers. The original sends id 0 alone.
A `listserver.txt` next to the program (host on the first line, port on the
second) names another.

## Units

Same split as the 2.05 rev 2 rebuild, with the `205` units renamed `Nm24`.
`GraalClient.pas` is `ClientNm24.pas` here, so that `GraalNm24` is the first
`Graal*` file in the build folder.

## Where it finds its files

The program sits at the top of its folder and reads only that folder:

1. the folder itself, laid out as a NewMain install (`levels/`,
   `pics1.png`, ...), or the folder given with `--data`;
2. `graal-assets/nm24/`;
3. `graal-assets/common/`.

Nothing found: its own built-in graphics and starter level fill in.

Files this build opens, for the assets zip: `pics1.png`, `arrays.dat`,
`sprites.png`, `body.png`, `state.png`, `letters.png`, `levels/heads/`,
`levels/bodies/`, `levels/swords/`, `levels/shields/`, `levels/ganis/`,
`maps/newmainmap.png` with `maps/newmainmap.txt`, `map.png`, and `sounds/`.

## Checks for 0.0.1

- Builds with Free Pascal on Linux and Windows; `TestNm24`,
  `TestEditorNm24` and `TestSoundMapNm24` pass.
- `scripts/loopback.sh` passes against seihai-gserver.
- Lab run under Wine (2026-11-04): the real exe and the rebuild each opened
  their start window, got the list from seihai-listserver and logged into
  seihai-gserver. The NewMain 24 archive holds only part of an install (no
  `headsconfig.txt`, and the original stops on that), so the real exe was
  run in the NewMain 26 install. The screenshots and login captures are in the project
  files, `graal-delphi/every-client-smoke/nm24/`.

## Not yet (0.0.2)

- The file requests at login (`sword1.png`, `shield1.png`, `head0.png`,
  `body.png`).
- The first gani system as NewMain had it, and the NewMain start window art.
- The 1.42 level and NPC features listed in `newfeatures142.txt`.
