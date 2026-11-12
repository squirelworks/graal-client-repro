# 1st Graal (`19980906`)

The 1st Graal client, rebuilt. Original: `Graal.exe` from the
`1stgraal-1` archive, 654,336 bytes, MD5 `07452f8941fdfcdce878b035156e701c`, linked
1998-09-06 23:54 (resource-directory stamp). A 1998 relay client
(generation 1): no account, no version token, no compression. The folder
carries the link date where later builds carry their token (see the folder
naming rule for tokenless builds in the project plan).

## Sources

Everything here is written from the notes in
[graal_analysis](https://github.com/squirelworks/graal_analysis), not from
decompiled code:

| Area | Notes |
|---|---|
| This build's profile | `client-internals/version-profiles/v1998-v11.toml` ("1st Graal") |
| Lobby lines, D payloads, game names | `protocol/relay-1998.md` |
| Two connections, pairing, state push, P encoding | `client-internals/live-trace-early.md` (1998 relay captures) |
| Level rooms | `client-internals/relay-room-bridge.md` |
| Build facts (date, size, MD5, magics) | `client-internals/build-catalogue.md` |
| Levels | `formats/level-binary-client.md` |
| Walking probe and nudge geometry | Exact-build behavior record `GRAAL-FIRST-MOVEMENT-20261109-01`, summarized below |

## Units

| Unit | What it does |
|---|---|
| `../common/GRelay.pas` | the relay lines, the two-character sender id, +32 numbers, one relay connection |
| `src/ProtocolB1.pas` | this build's game name, D types, level magics, colour count, connect dialog |
| `src/Adventure.pas` | game state: level, walking, the two relay connections, partners, drawing |
| `src/GraalB1.dpr` | front end: the original's start dialog with no arguments (the shared start screen without Win32), or the command line |
| `src/RealResB1.pas` | the original program's resources (forms, pictures, strings), from `scripts/realres/extract_res.py` |
| `../common/GDfmObj.pas`, `../common/GVclForm.pas` | reading Delphi forms and showing them as native windows |
| `../common/GBetaStart.pas` | the 1998 start dialog: character lists, modes, what the player picked |
| `src/StartScreenB1.pas` | the connect dialog as the one row of the shared start screen's list |
| `src/RunMode.pas` | stress-run support (clock, stop signals, tick histogram, walker, JSON) |

## What works (0.0.1)

- Offline: loads this build's level formats (Z3-V1.03, Z3-V1.04) and walks
  with collision from the install's `arrays.dat`. Other level formats are
  refused, as the original had no reader for them.
- Online: two connections to the relay, as the original opens: `Zelda2` as the fixed game; on a level, `Z` + the level's base name + `2` (`house1.graal` gives `Zhouse12`).
  Each sends `N<game>#def`, takes its id from `I`, answers every `+` with
  `P`, and after each pairing pushes its state (L, P, N, S, T; only
  the types this build sends). While walking it sends `P` every 100 ms
  (x and y in half tiles, frame*4 + direction), and the idle frame on stop.
- Partners' `P`, `N`, `S`, `L`, `T`, `C`, `I` and `Y` are read; partners are
  drawn on the level.
- The start screen: nick name, Training (this build's start level, or the
  built-in starter level), and Start, which shows the connect dialog's
  relay (this build had no pre-filled relay host; the rebuild offers `listserver.graal.in:14801` (14801 is the build's compiled-in default port)). `listserver.txt` next to the program replaces it.
- The original used an event-driven socket component; the rebuild polls a plain socket from the frame loop, like the later builds.
- Tests: lobby lines, sender ids, the walking `P` line from a capture,
  rooms, level formats, walking, and 20000 random payloads through the
  receive path. CI joins two copies to the lab relay
  (`scripts/relay98.py`) and checks that each sees the other.

## Start dialog and window (0.0.3)

With no arguments on Windows the program shows the original's own start
dialog, built from the `TConnectFrame` form in `res/TCONNECTFRAME.dfm`: One Player, Two Player and One Player Online radio buttons with the server and port fields.
The window is owned by the program's hidden application window, as in the 1st to 5th Graal.
Start opens the game in a window shaped as the `TAdventure` form
(`res/TADVENTURE.dfm`). Under Wine, real and rebuilt dialogs were
screenshotted side by side and match pixel for pixel.

## Exact-build walking geometry (v0.0.5)

- [x] Use this executable's half-tile step, six ordered probes and
  eighth-tile corner nudges, rather than later builds' constants.
- [ ] Match the rest of the movement state machine: pushing counters,
  ledge/hop gates and exceptional movement states.

The source is researcher-supplied behavior record
`GRAAL-FIRST-MOVEMENT-20261109-01`, reproduced as original prose in the
[sanitized evidence handoff](MOVEMENT_EVIDENCE.md). The REA researcher
supplied the executable identity, hash verification and static observations;
this implementation PR and its supervisor have not independently verified
the original executable or its hash. The newer record narrows the older
public Appendix E307, which has not yet incorporated these findings. It
establishes static geometry, not measured input timing or a complete
gameplay match.

Each walking candidate moves half a tile in the facing direction. The six
blocked-point tests are taken at these offsets from that candidate, in order:

- Up: X offsets 0.6, 1.4, 1.6, 2.4, 2.525, 0.475, all at Y + 1.05.
- Left: Y offsets 1.1, 1.9, 2.1, 2.9, 3.025, 0.975, all at X + 0.55.
- Down: the up X offsets, all at Y + 2.95.
- Right: the left Y offsets, all at X + 2.45.

When probe 0 blocks and probes 2, 3 and 4 are clear, the free axis moves
+0.125 tiles. When probes 0 and 1 are clear, probe 3 blocks and probe 5 is
clear, it moves -0.125. Up/down nudge X; left/right nudge Y. If any of
probes 0 through 3 blocks, the facing step is undone while the nudge stays.
The probes are not collected again after nudging. Synthetic-board tests
exercise both nudge signs and free movement in every direction, plus
boundary cases that distinguish this build from the previous constants.

The existing final near-grid snap and tile classification remain inherited
behavior; this bounded evidence does not establish them as exact for this
build. The remaining movement state gates are also not certified by these
tests.

## Not yet (0.0.2 and later)

- [x] The player is drawn from the install's own body sheet (`link.gif` or
  `sprites.gif`) and `heads.gif`, with the pose and sprite tables of its
  `arrays.dat` (`../common/GBetaPlayer.pas`).
- [ ] Only Nick's colours were measured on the real client; the other
  characters are drawn in Nick's colours with their own heads.
- [ ] Chat, items, sword, bombs, arrows, baddies, NPC scripts, signs, saves
  (Graalsav1 `.save`), the local multiplayer modes, web levels over
  HTTP, sound.
- [ ] Comparison with the original under Wine, action by action.

## Assets this build reads

From the program's folder, `graal-assets/b1/` or `graal-assets/common/`
(or `--data`): `pics1.gif` (or `.png`), `arrays.dat`, and levels from
`levels/` or the folder itself (`level1.graal` is the Training level).
Without them it uses its built-in assets.

## Running it

```
GraalB1                                                # start dialog
GraalB1 --level levels/level1.graal --data /path/to/install --window
GraalB1 --server 127.0.0.1:14802 --nick NAME --data /path/to/install
```
