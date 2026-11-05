# 15th Graal (V1.1) (`19990125`)

The 15th Graal (V1.1) client, rebuilt. Original: `Graal.exe` from the
`15thgraal` archive, 878,592 bytes, MD5 `9a7d66dd5c8c506ad4d3e63ee4a9a1f1`, linked
1999-01-25 00:12 (resource-directory stamp). A 1998 relay client
(generation 1): no account, no version token, no compression. The folder
carries the link date where later builds carry their token (see the folder
naming rule for tokenless builds in the project plan).

## Sources

Everything here is written from the notes in
[graal_analysis](https://github.com/squirelworks/graal_analysis), not from
decompiled code:

| Area | Notes |
|---|---|
| This build's profile | `client-internals/version-profiles/v1998-v11.toml` ("15th Graal (V1.1)") |
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
| `src/ProtocolB15.pas` | this build's game name, D types, level magics, colour count, connect dialog |
| `src/Adventure.pas` | game state: level, walking, the two relay connections, partners, drawing |
| `src/GraalB15.dpr` | front end: the start screen with no arguments, or the command line |
| `src/StartScreenB15.pas` | the connect dialog as the one row of the shared start screen's list |
| `src/RunMode.pas` | stress-run support (clock, stop signals, tick histogram, walker, JSON) |

## What works (0.0.1)

- Offline: loads this build's level formats (GR-V1.00, GR-V1.01, GR-V1.02, GR-V1.03, Z3-V1.03, Z3-V1.04) and walks
  with collision from the install's `arrays.dat`. Other level formats are
  refused, as the original had no reader for them.
- Online: two connections to the relay, as the original opens: `Graal8` as the fixed game; on a level, `G8` + the level file name (`G8level1.graal`).
  Each sends `N<game>#def`, takes its id from `I`, answers every `+` with
  `P`, and after each pairing pushes its state (L, P, N, S, 7, T, Y; only
  the types this build sends). While walking it sends `P` every 100 ms
  (x and y in half tiles, frame*4 + direction), and the idle frame on stop.
- Partners' `P`, `N`, `S`, `L`, `T`, `C`, `I` and `Y` are read; partners are
  drawn on the level.
- The server's level choice: after `N` the relay answers `NR` then `NL` (local levels: start on `onlinestartlocal.graal`) or `NR` alone (web levels: `onlinestart.graal`). The level game is joined after it.
- The start screen: nick name, Training (this build's start level, or the
  built-in starter level), and Start, which shows the connect dialog's
  relay (pre-filled with `listserver.graal.in:14802` (the original was pre-filled with the relay operator's host)). `listserver.txt` next to the program replaces it.
- Plain WinSock in the original (blocking connect, then non-blocking reads polled from the frame loop); the rebuild does the same through `common/GSocket.pas`.
- Tests: lobby lines, sender ids, the walking `P` line from a capture,
  rooms, level formats, walking, and 20000 random payloads through the
  receive path. CI joins two copies to the lab relay
  (`scripts/relay98.py`) and checks that each sees the other.

## Not yet (0.0.2 and later)

- [ ] The player is drawn with the project's built-in stand-in art; this
  build's own `sprites.gif` layout is not written up yet.
- [ ] Chat, items, sword, bombs, arrows, baddies, NPC scripts, signs, saves
  (Graalsav7 `.gsave`), the local multiplayer modes, web levels over
  HTTP, sound.
- [ ] Comparison with the original under Wine, action by action.

## Assets this build reads

From the program's folder, `graal-assets/b15/`, `graal-assets/b11/` or `graal-assets/common/`
(or `--data`): `pics1.gif` (or `.png`), `arrays.dat`, and levels from
`levels/` or the folder itself (`level1.graal` is the Training level).
Without them it uses its built-in assets.

## Running it

```
GraalB15                                                # start screen
GraalB15 --level levels/level1.graal --data /path/to/install --window
GraalB15 --server 127.0.0.1:14802 --nick NAME --data /path/to/install
```
