# Graal 2.05 rev 2 (`GNW03081`)

The 2.05 rev 2 client, rebuilt. Original: `Graal v2.05 rev2.exe`, 1,891,840
bytes, Delphi 4/5 with DelphiX and zlib 1.1.2. The 2.0 era client and editor
in one program.

## Sources

Everything here is written from the notes in
[graal_analysis](https://github.com/squirelworks/graal_analysis), not from
decompiled code:

| Area | Notes |
|---|---|
| Classes and their split | `client-internals/client-architecture-205.md` |
| Framing, zlib, gen-3 cipher | `protocol/codec-and-framing.md` |
| Login line | `protocol/login-and-walk.md`, `client-internals/version-tokens.md` |
| Message ids | `protocol/packet-ids.md` (2.05 column) |
| Player props | `protocol/player-props.md` (pre-2.1 forms) |
| Levels | `formats/level-binary-client.md`, `formats/glevnw01.txt` |
| Tile sheet | `client-internals/client-assets.md` |
| Frame loop | `client-internals/rendering-observations.md` |

## Units

| Unit | 2.05 class | What it does |
|---|---|---|
| `src/Protocol205.pas` | | ids, token, cipher constants, buffer limits |
| `src/GraalClient.pas` | `TGraalClient`, `TAdventureClient` | out buffer, zlib frames, gen-3 insertion, login, receive split with `PLO_RAWDATA` |
| `src/Adventure.pas` | `TAdventure`, `TServerPlayer` | game state, message handlers, 50 ms tick, drawing |
| `src/Graal205.dpr` | | command line front end |

## What works

- Login exactly as 2.05 sends it: type 0, gen-3 key, `GNW03081`, account,
  password, then `PLI_LANGUAGE`. Every message after the login line carries
  the gen-3 byte. The junk positions match a real 2.05 capture (test).
- Server frames: u16be + zlib, split on LF, `PLO_RAWDATA` blocks across
  frame boundaries.
- Handlers for the login burst: player props (pre-2.1 forms), warp, level
  name, board packet, links, signs, chests, signature, world time, start
  and disconnect messages, set active level.
- Levels from disk: GR-V1.00 to 1.03, Z3-V1.03/1.04, GLEVNW01. All 13 tutorial
  levels embedded in the original exe decode to the published tiles, and
  their boards re-encode byte for byte with the 2.05 writer rules (test, with
  the levels supplied locally).
- Drawing: the board from `pics1` with the 2.05 sheet layout, centred on the
  player, into a 640x480 frame.
- Loopback: logs into seihai-gserver, gets the burst, loads the board
  (`scripts/loopback.sh`, run in CI).

## Not yet

- A window and input. The player is drawn as a box; no sprites, ganis,
  heads or bodies.
- Sending props (2.05 sends {0, 11, 13, 18, 31, 33} at session start, and
  position changes per tick), movement, level links, UDP peer traffic.
- Most of the 59 server ids 2.05 handles: 14 have real handlers so far. NPCs, baddies, other players, items,
  weapons and the rest of the game.
- The GS1 script engine (161 commands), the built-in editors.
- The listserver link (DES-hidden host, `newmain`).
- The window size (640x480 is assumed, not read from the binary).
- Phase 4 hardening (see the top-level README).
