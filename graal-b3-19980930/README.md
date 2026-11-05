# 3rd Graal (`19980930`)

The 3rd Graal client, rebuilt. Original: `Graal.exe` from the
`3rdgraal` archive, 665,600 bytes, MD5 `fc78fbc96bdbc6ca22ae56d3ed8635ab`, linked
1998-09-30 01:47 (resource-directory stamp). A 1998 relay client
(generation 1): no account, no version token, no compression. The folder
carries the link date where later builds carry their token (see the folder
naming rule for tokenless builds in the project plan).

## Sources

Everything here is written from the notes in
[graal_analysis](https://github.com/squirelworks/graal_analysis), not from
decompiled code:

| Area | Notes |
|---|---|
| This build's profile | `client-internals/version-profiles/v1998-v11.toml` ("3rd Graal") |
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
| `src/ProtocolB3.pas` | this build's game name, D types, level magics, colour count, connect dialog |
| `src/Adventure.pas` | game state: level, walking, the two relay connections, partners, drawing |
| `src/GraalB3.dpr` | front end: the start screen with no arguments, or the command line |
| `src/StartScreenB3.pas` | the connect dialog as the one row of the shared start screen's list |
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

## Not yet (0.0.2 and later)

- [ ] The player is drawn with the project's built-in stand-in art; this
  build's own `sprites.gif` layout is not written up yet.
- [ ] Chat, items, sword, bombs, arrows, baddies, NPC scripts, signs, saves
  (Graalsav1 `.save`), the local multiplayer modes, web levels over
  HTTP, sound.
- [ ] Comparison with the original under Wine, action by action.

## Assets this build reads

From the program's folder, `graal-assets/b3/` or `graal-assets/common/`
(or `--data`): `pics1.gif` (or `.png`), `arrays.dat`, and levels from
`levels/` or the folder itself (`level1.graal` is the Training level).
Without them it uses its built-in assets.

## Running it

```
GraalB3                                                # start screen
GraalB3 --level levels/level1.graal --data /path/to/install --window
GraalB3 --server 127.0.0.1:14802 --nick NAME --data /path/to/install
```
