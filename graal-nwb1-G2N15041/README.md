# Graal NewWorld beta 1 (`G2N15041`)

The NewWorld beta 1 client, rebuilt. Original: `Graal-NW.exe` from GraalNW1, 1,820,672 bytes (CRC32 `D5200A29`, MD5 `88d1f84c96da1dcc3942b139fbd741c9`, linked 2001-08-06, FileVersion 2.0.5.0), Delphi with DelphiX and zlib, built on the 2.05 client. The NewWorld betas were the
client for the NewWorld test servers ("NewWorld: The Euphraites Isles"), with
their own tile sheets, string arrays, terrain heights and a world clock. All
three NewWorld exes send the token `G2N15041`.

The same archive holds an older exe, `Graal-NW.exe.dclientbackup` (2.0.3.0), which the NewWorld updater replaced. It has its own folder, `graal-nwb1pre-G2N15041`.

This folder starts as a copy of `graal-2.05r2-GNW03081`. It is changed where
the version notes (graal_analysis `version-profiles/141-217.md`) and the lab
runs say the NewWorld beta differs. Version 0.0.1 carries the differences a
server or a player sees first. The rest is listed under "Not yet".

## What differs from the 2.05 rev 2 rebuild

| | NewWorld beta 1 | 2.05 rev 2 |
|---|---|---|
| Token | `G2N15041` | `GNW03081` |
| Listserver list | `newworld`, id 0 only (built-in port 14921) | `newmain` |
| Prop 10 | the gani by name (`GSTRING`), sent at login and when it changes | the bow |
| Prop 13 (colours) | eight bytes, sent and read | five |
| Player props read | own 0 to 42, others as 2.05 | own 0 to 42 |
| Built-in sword, bow, bombs, baddies | none: S does nothing unless a weapon NPC does it; `DEFAULTWEAPON` and `BADDYPROPS` are dropped | built in |
| Tile sheet, tile types, sprites, default body | `pics1nw.png`, `arraysnw.dat`, `spritesnw.png`, `bodynw.png` (the classic names as fallback) | `pics1.png`, `arrays.dat`, `sprites.png`, `body.png` |

The game login was checked on the real exe in the Wine lab (2026-11-04). It
sends the login line, LANGUAGE `English`, file requests for `shield1.png`,
`head0.png`, `body.png` and `timenums.png`, flag sets from its control NPC,
and props 0, 11, 13 (eight colour bytes), 18, 31 and 33, then prop 10
`idle`. The version notes say "sends 7 colour bytes". The capture shows 8.
The rebuild sends the login line, LANGUAGE, the login props and the gani. The
file requests and flags come from the control NPC script and are left for
0.0.2.

seihai-gserver has no profile for `G2N15041`. It logs the client in as an
"unknown build" once the token is in the world's `allowedversions.txt`.

## The listserver

Default: `listserver.graal.in`, port 14923. The rebuild asks for the
`newworld` list with id 0, then sends id 1 with the account and password,
the classic login the public legacy port answers. A `listserver.txt` next to
the program (host on the first line, port on the second) names another.

## Units

Same split as the 2.05 rev 2 rebuild, with the `205` units renamed `Nwb1`.
`GraalClient.pas` is `ClientNwb1.pas` here, so that `GraalNwb1` is the first
`Graal*` file in the build folder.

## Where it finds its files

The program sits at the top of its folder and reads only that folder:

1. the folder itself, laid out as a NewWorld install (`levels/`,
   `pics1nw.png`, ...), or the folder given with `--data`;
2. `graal-assets/nwb1/`;
3. `graal-assets/common/`.

Nothing found: its own built-in graphics and starter level fill in.

Files this build opens, for the assets zip: `pics1nw.png`, `arraysnw.dat`,
`spritesnw.png`, `bodynw.png`, `state.png`, `letters.png`, `levels/heads/`,
`levels/bodies/`, `levels/swords/`, `levels/shields/`, `levels/ganis/`
(`idle`, `walk` and the other player ganis), `bigmap.txt`, `map.png`,
`minimap.txt`, and `sounds/`.

## Checks for 0.0.1

- Builds with Free Pascal on Linux and Windows; `TestNwb1`,
  `TestEditorNwb1` and `TestSoundMapNwb1` pass.
- `scripts/loopback.sh`, with the change that lets the temporary world allow
  the build's own token (#47), passes against seihai-gserver.
- Lab run under Wine (2026-11-04): the real exe and the rebuild each opened
  their start window, got the list from seihai-listserver and logged into
  seihai-gserver. The screenshots and login captures are in the project
  files, `graal-delphi/every-client-smoke/nwb1/`.

## Not yet (0.0.2)

- The NewWorld HUD: 150/150 health and the calendar clock from the world
  time (message 42).
- The local control NPC (`controlnpc.txt`) that drives movement, file
  requests and flags in the original, and the gani prop re-sent every
  100 ms.
- String arrays and terrain heights in GS1 and levels, back tiles.
- The NewWorld start window art and the server list theme.
