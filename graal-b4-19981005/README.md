# 4th Graal (`19981005`)

The 4th Graal client, rebuilt. Original: `Graal.exe` from the
`4thgraal` archive, 666,112 bytes, MD5 `e040af2e19912419ab80aa6dd202b4ea`, linked
1998-10-05 01:33 (resource-directory stamp). A 1998 relay client
(generation 1): no account, no version token, no compression. The folder
carries the link date where later builds carry their token (see the folder
naming rule for tokenless builds in the project plan).

## Sources

Everything here is written from the notes in
[graal_analysis](https://github.com/squirelworks/graal_analysis), not from
decompiled code:

| Area | Notes |
|---|---|
| This build's profile | `client-internals/version-profiles/v1998-v11.toml` ("4th Graal") |
| Lobby lines, D payloads, game names | `protocol/relay-1998.md` |
| Two connections, pairing, state push, P encoding | `client-internals/live-trace-early.md` (1998 relay captures) |
| Level rooms | `client-internals/relay-room-bridge.md` |
| Build facts (date, size, MD5, magics) | `client-internals/build-catalogue.md` |
| Levels | `formats/level-binary-client.md` |
| Walking and collision | `client-internals/decomp-findings-2026-10-25-m/01-walking-rule.md` (later builds; not yet checked on this one) |

## Units

| Unit | What it does |
|---|---|
| `../common/GRelay.pas` | the relay lines, the two-character sender id, +32 numbers, one relay connection |
| `src/ProtocolB4.pas` | this build's game name, D types, level magics, colour count, connect dialog |
| `src/Adventure.pas` | game state: level, walking, the two relay connections, partners, drawing |
| `src/GraalB4.dpr` | front end: the original's start dialog with no arguments (the shared start screen without Win32), or the command line |
| `src/RealResB4.pas` | the original program's resources (forms, pictures, strings), from `scripts/realres/extract_res.py` |
| `../common/GDfm.pas`, `../common/GVclForm.pas` | reading Delphi forms and showing them as native windows |
| `../common/GBetaStart.pas` | the 1998 start dialog: character lists, modes, what the player picked |
| `src/StartScreenB4.pas` | the connect dialog as the one row of the shared start screen's list |
| `src/RunMode.pas` | stress-run support (clock, stop signals, tick histogram, walker, JSON) |

## What works (0.0.1)

- Offline: loads this build's level formats (GR-V1.00, GR-V1.01, Z3-V1.03, Z3-V1.04) and walks
  with collision from the install's `arrays.dat`. Other level formats are
  refused, as the original had no reader for them.
- Online: two connections to the relay, as the original opens: `Graal` as the fixed game; on a level, `G` + the level file name (`Glevel1.graal`).
  Each sends `N<game>#def`, takes its id from `I`, answers every `+` with
  `P`, and after each pairing pushes its state (L, P, N, S, T; only
  the types this build sends). While walking it sends `P` every 100 ms
  (x and y in half tiles, frame*4 + direction), and the idle frame on stop.
- Partners' `P`, `N`, `S`, `L`, `T`, `C`, `I` and `Y` are read; partners are
  drawn on the level.
- The start screen: nick name, Training (this build's start level, or the
  built-in starter level), and Start, which shows the connect dialog's
  relay (pre-filled with `listserver.graal.in:14802` (the original was pre-filled with the relay operator's host)). `listserver.txt` next to the program replaces it.
- Plain WinSock in the original (blocking connect, then non-blocking reads polled from the frame loop); the rebuild does the same through `common/GSocket.pas`.
- Tests: lobby lines, sender ids, the walking `P` line from a capture,
  rooms, level formats, walking, and 20000 random payloads through the
  receive path. CI joins two copies to the lab relay
  (`scripts/relay98.py`) and checks that each sees the other.

## Start dialog and window (0.0.3)

With no arguments on Windows the program shows the original's own start
dialog, built from the `TConnectFrame` form in `res/TCONNECTFRAME.dfm`: One Player and Two Players with a character list each, and the "Online At Cyberjoueur" group with nick name, server and port.
The window is owned by the program's hidden application window, as in the 1st to 5th Graal, and stays on top.
The character lists hold Fung Si Yan, Nick, Mandi, Bad Max, Pachuka, Blond, each with its head from `heads.gif`.
Start opens the game in a window shaped as the `TAdventure` form
(`res/TADVENTURE.dfm`). Under Wine, real and rebuilt dialogs were
screenshotted side by side and match pixel for pixel.

## Not yet (0.0.2 and later)

- [ ] The player is drawn with the project's built-in stand-in art; this
  build's own `sprites.gif` layout is not written up yet.
- [ ] Chat, items, sword, bombs, arrows, baddies, NPC scripts, signs, saves
  (Graalsav1 `.save`), the local multiplayer modes, web levels over
  HTTP, sound.
- [ ] Comparison with the original under Wine, action by action.

## Assets this build reads

From the program's folder, `graal-assets/b4/` or `graal-assets/common/`
(or `--data`): `pics1.gif` (or `.png`), `arrays.dat`, and levels from
`levels/` or the folder itself (`level1.graal` is the Training level).
Without them it uses its built-in assets.

## Running it

```
GraalB4                                                # start dialog
GraalB4 --level levels/level1.graal --data /path/to/install --window
GraalB4 --server 127.0.0.1:14802 --nick NAME --data /path/to/install
```
