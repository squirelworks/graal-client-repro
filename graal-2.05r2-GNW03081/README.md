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
| Walking and collision | `client-internals/decomp-findings-2026-10-25-m/01-walking-rule.md` |
| Ganis | `formats/gani.txt` |
| Body colours | `client-internals/body-colours-and-attributes.md` |
| Tile types | `formats/arrays-and-signatures.md` |

## Units

| Unit | 2.05 class | What it does |
|---|---|---|
| `src/Protocol205.pas` | | ids, token, cipher constants, buffer limits |
| `src/GraalClient.pas` | `TGraalClient`, `TAdventureClient` | out buffer, zlib frames, gen-3 insertion, login, receive split with `PLO_RAWDATA` |
| `src/Adventure.pas` | `TAdventure`, `TServerPlayer` | game state, message handlers, 50 ms tick, drawing |
| `src/Graal205.dpr` | | command line front end: window, scripted keys, frame dump |

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
  player, into a 640x480 frame. The player is drawn from the install's ganis
  (`idle`, `walk`) with head, body, sword and shield images, and the body is
  recoloured from the five colour props.
- A window (X11 on Linux, GDI on Windows) with keyboard input: arrows or
  IJKL walk, Esc quits. `--keys` drives the same input from a script, so
  headless runs can walk too.
- Walking with the 2.05 rule: half-tile steps, six probes per facing, the
  0.1 corner nudge, keys taken in the order up, left, down, right. Blocking
  comes from `arrays.dat` tile types and level chests (tests).
- Props out: the session-start set {0, 11, 13, 18, 31, 33}, then position,
  direction and sprite whenever they change, at most every 100 ms.
- Loopback: logs into seihai-gserver, gets the burst, loads the board and
  walks a few steps (`scripts/loopback.sh`, run in CI).

## Not yet

- Walk sprite frames on the wire: the `PLPROP_SPRITE` value 2.05 sends while
  walking is not in the notes yet, so only the direction is sent.
- Level links (warping by walking off a link), UDP peer traffic, other
  players' movement.
- Most of the 59 server ids 2.05 handles. NPCs, baddies, items, weapons
  and the rest of the game.
- The GS1 script engine (161 commands), the built-in editors.
- The listserver link (DES-hidden host, `newmain`).
- The window size (640x480 is assumed, not read from the binary). The
  board edge is treated as open.
- Phase 4 hardening (see the top-level README).
