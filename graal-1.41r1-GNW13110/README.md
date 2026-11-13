# Graal 1.41 rev 1 (`GNW13110`)

The 1.41 rev 1 client, rebuilt. Original: `Graal.exe` 1.41 rev 1, 1,506,816
bytes (SHA-256 `fdf0aff28d5e400a2ff83be09f56b89a8f9b84d0502ecdeaeaa36e461c45dc8b`,
from `Graal v1.41r1.rar`), Delphi with DelphiX and zlib. The token dates it
13 Nov 2000. It is the first build of the third generation: the gen-3
cipher and the key byte in the login line, and the first build with a
server list window.

## Which copy is the original

Three copies of the 1.41r1 exe are held, all FileVersion 1.4.1.1 and all
1,506,816 bytes. They were compared byte for byte on 2026-11-13:

| Copy | SHA-256 | Listserver | Server list title, links |
|---|---|---|---|
| `Graal v1.41r1.rar` (Batch-1 variant A) | `fdf0aff2…` | `www.graalonline.com` 14910 | "Graalonline.com Server List", graalonline.com |
| installed folder `Graal_v1.41r1\` (Batch-1 variant B) | `b08c8d14…` | `listserver.graal.in` 14923 | as variant A |
| `graal_1411\` (MD5 `a97740e7…`, the copy this folder was first built from) | `281b752a…` | `listserver.graal.in` 14923 | "Graal.in Server List", graal.in links |

Variant A is the unpatched original. The graal.in copy was patched in two
steps. Variant B changes only the listserver host and port and where the
game window's "Edit flags" button enters its click
handler: further in, so the start of the handler is skipped. What that
start does has not been read yet; it is listed under "Not yet". The
`graal_1411` copy keeps both and adds the graal.in title, hints and links
in the server list form and the web links. Nothing else differs: the
token, the gen-3 cipher, the login, the message handling and every other
embedded form, picture and icon are the same bytes in all three (the
`graal_1411` copy's cursor directory headers differ too, as a resource
editor leaves them). So the
token and cipher this folder sends stand as they were, the forms and icon
compiled in from the patched copy are the original's, and only the server
list title changed (it now reads "Graalonline.com Server List").

This folder starts as a copy of `graal-2.05r2-GNW03081` and is changed where
the version notes (graal_analysis `version-profiles/141-217.md`, "1.41 rev1")
say 1.41 differs. Version 0.0.1 carries the differences a server or a player
sees first; the rest is listed under "Not yet".

## What differs from the 2.05 rev 2 rebuild

| | 1.41 rev 1 | 2.05 rev 2 |
|---|---|---|
| Token | `GNW13110` | `GNW03081` |
| After the login line | nothing | `PLI_LANGUAGE` (37) |
| Head prop (11) at login | its number, below 100, for `headN.gif` | `c(100 + length)` and the name |
| Player props read | 0 to 36; a higher id ends the stream | 0 to 42 (own), 0 to 51 (others) |
| Server messages handled | 0 to 41, 43, 75, raw data (100) | adds 42, 44 to 48, 150 on |
| Start window | game mode (One Player, One Player Online, Two to Four Players), character, nick name, Start | character, Training, Start |
| Offline play | One Player on the install's `start1.graal` | Training (tutorial levels) |
| Animations | sprite numbers only (no `.gani`) | `.gani` |

The level formats (GR-V1.00 to 1.03 and GLEVNW01), the gen-3 cipher, zlib
framing, the pre-2.1 prop forms and the classic level send are the same as
in 2.05.

## Units

Same split as the 2.05 rev 2 rebuild, with the `205` units renamed `141`:

| Unit | What it does |
|---|---|
| `src/Protocol141.pas` | ids, token, the props and messages 1.41 reads |
| `src/GraalClient.pas` | out buffer, zlib frames, gen-3 insertion, login |
| `src/Adventure.pas` | game state, message handlers, tick, drawing |
| `src/Graal141.dpr` | front end: the start window with no arguments, or the command line |
| `src/StartWindow141.pas` | the 1.41 start window and server list (its own copy of `common/GStartScreen.pas`, because 1.41 opens on a game-mode window) |
| `src/StartScreen141.pas` | its listserver step and its character |
| `src/Npc141.pas`, `src/NpcBridge141.pas`, `src/Baddy141.pas`, `src/Sound141.pas`, `src/Map141.pas`, `src/RunMode.pas`, `src/editor/` | as in the 2.05 rev 2 rebuild |

## The listserver

The real 1.41 opens a plain zlib link to the listserver and sends nothing;
the server sends the list. The unpatched exe asks `www.graalonline.com` on
port 14910, which no longer answers. This was checked in the lab on 2026-11-04: the
real exe under Wine connected to `seihai-listserver` on 14923 and sent no
byte until the list came. The public listserver's legacy port answers only
a classic login, so the rebuild sends one (id 0 `newmain`, then id 1 with
the account and password), as the 2.05 rebuild does. Default:
`listserver.graal.in`, port 14923. A `listserver.txt` next to the program
(host on the first line, port on the second) names another.

## Where it finds its files

The program sits at the top of its folder and reads only that folder:

1. the folder itself, laid out as a 1.41 install (`levels/`, `sounds/`,
   `pics1.png`, ...), or the folder given with `--data`;
2. `graal-assets/1.41r1/`;
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

- Builds with Free Pascal on Linux and Windows; `Test141`, `TestEditor141`
  and `TestSoundMap141` pass.
- `scripts/loopback.sh`: two copies log into seihai-gserver, which reads
  them as `GNW13110 1.41, Gen3`; the second sees the first; a level link
  works.
- Lab run under Wine (2026-11-04): the real 1.41 and the rebuild each
  opened their start window, got the server list from seihai-listserver and
  logged into seihai-gserver. One Player walks on `start1.graal`.

## Seihai secure login (not in the original)

Off by default, so the login is byte for byte the original's. With
`--secure-login auto` or `required` (or one word in `secure_login.txt` in
the shared settings folder), the account and the password go sealed to a
Seihai game server (version token `SEI00001`, graal-client-repro #148).
C1 carries the type and key bytes of the classic login and this build's token, and
C2 stands in for the login line. What the build sends with its login line follows C2 in the same frame, gen-3 coded from the first step. Same code and settings as 2.31: see the 2.31 README,
"Seihai secure login". CI logs in once more with `--secure-login required`
(`scripts/loopback.sh`).

## Not yet (0.0.2)

- [ ] What the start of the original's "Edit flags" click handler does (the
  graal.in copies skip it), and whether the rebuild's Edit flags matches.
- [ ] Drawing from the 1.41 sprite sheet. The wire already carries 1.41 sprite
  numbers, but the rebuild still draws through its own poses.
- [ ] Two to four players on one computer, save games, the F1 options window.
- [ ] The 1.41 HUD (AP bar, sparring label) and the 1.41 GS1 command set (126
  commands; the rebuild still has the 2.05 set).
