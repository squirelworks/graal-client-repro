# Graal 1.1 (linked 1999-02-14)

The 1.1 client, rebuilt. Original: `Graal.exe` 1.1, 882,176 bytes (MD5
`1a9580655cce686c602c01daa251c453`, linked 1999-02-14), Delphi with
DirectX. Game, relay client and level editor in one program.

1.1 sends no version token, so the folder carries the link date in the
token's place (`graal-<version>-<YYYYMMDD>`, the rule for tokenless builds).

This folder starts as a copy of `graal-1.1.9-19990211`. 1.1 was linked
three days after the 1.1.9 "Gold Edition" and is the same size. Its
strings name the same relay game (`Graal8`), the same save magic
(Graalsav7/8), the same start levels and the same connect dialog; its game
modes stop at Two Players (1.1.9 also lists Three and Four Players). So the
code is the same apart from the labels.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

## Sources

Everything here is written from the notes in
[graal_analysis](https://github.com/squirelworks/graal_analysis), not from
decompiled code:

| Area | Notes |
|---|---|
| The relay link: lines, ids, games, D types | `protocol/relay-1998.md` |
| Two links, level rooms, NR / NL, the walk capture | `client-internals/live-trace-early.md` |
| Build facts (link date, game `Graal8`, connect dialog) | `client-internals/build-catalogue.md` |
| Save files (Graalsav7/8, `.gsave`) | `formats/graalsav.md` |
| Levels | `formats/level-binary-client.md` |
| Tile types | `formats/arrays-and-signatures.md` |
| Everything kept from the copied build | the table in `graal-2.05r2-GNW03081/README.md` |

## Units

| Unit | 1.1 class | What it does |
|---|---|---|
| `src/Protocol11.pas` | | generation 1, no token, the relay game names, start levels, the event numbers the game code uses |
| `src/GraalClient.pas` | `TAdventureClient` | over `common/GRelay.pas` (the shared gen-1 line codec and connection): the two relay links (game `Graal8` and the level room `G8<level>`), pairing, the state push, D lines to and from game events |
| `src/Adventure.pas` | `TAdventure` | game state, the 50 ms tick, drawing; online it plays the player's own levels and tells the room what happens |
| `src/StartScreen11.pas` | (`TConnectFrame`) | game mode (One Player, One Player Online) and the connect dialog |
| `src/Graal11.dpr` | | front end: the start with no arguments, or the command line |
| other units | | as in the copied build (NPCs and GS1, baddies, sound, map, editor, stress-run support) |

## What works at 0.0.1

- The relay link as 1.1 opens it: two TCP links to one host and port,
  `NGraal8#def` on one and `NG8#def` then `NG8<level>#def` on the other;
  each announced player is asked to pair (`P<id>`), and on a pairing the
  state is pushed: login time (`T`, ten base-128 characters), nickname
  (`N`), five colours (`S`), position (`P`). Walking sends `P` (x and y in
  half tiles, frame*4 + direction) at most every 100 ms, and a link sends
  `I` and moves the level link to the new room. Board changes go out and
  come in as `B` (w*8+h). Tested against the walk bytes captured from two
  real 1.1.9 clients (no 1.1 capture exists; its strings hold the same
  join line).
- Peers' `P`, `N`, `S`, `C`, `I` and `B` lines are applied; the other
  D types are counted and not applied yet.
- NR / NL after the join: with NL the client moves from
  `onlinestart.graal` to `onlinestartlocal.graal` when the player has it.
- One Player on `levels/level1.graal` (the single-player start level),
  walking and collision on the 1.1 tiles, links, the copied game code.
- The start: a game mode page and a connect dialog filled with
  `listserver.graal.in:14802` (or what `listserver.txt` next to the
  program names). 1.1 filled it with the Cyberjoueur relay on 14802,
  which is gone.

## Known differences at 0.0.1

- The 1.1 `arrays.dat` holds 24 tables where the later clients read 25.
  Tables 0 and 1 (the passable tiles) are read from it; the rest are the
  built-in ones until it is known which table moved.
- 1.1's `sprites`, `state` and `letters` sheets have their own layouts.
  The built-in sheets are drawn until those layouts are read.
- The player is drawn from the built-in ganis; 1.1 had no ganis and drew
  from `sprites.gif` and `heads.gif`.
- `onlinestart.graal` was built into the original program. Without it the
  built-in start level stands in.
- A player met through the fixed `Graal8` game stays drawn until a level
  room says it left; the relay's `-` for a player never paired in the
  room is not applied. What 1.1 does with the `Graal8` pair after the
  first state push was not seen in the captures.
- Two Players (one keyboard), save games (`.gsave`), the
  registration key line (`8`) and web levels over HTTP are not built.

## Files it opens

From the folder the program is in, or `--data DIR`, then
`graal-assets/1.1/`, `graal-assets/1.1.9/`, `graal-assets/b15/`,
`graal-assets/b11/` and `graal-assets/common/`: `pics1.gif`, `arrays.dat`,
`levels/*.graal`, `sounds/*.wav`, `map.gif`. 1.1 shipped the same files as
1.1.9 except `pics1.gif` and `objects.dat`, so `graal-assets/1.1/` holds
only those two. Nothing above the program's folder is read.

## Build and run

```
scripts/build.sh graal-1.1-19990214
build/graal-1.1-19990214/Graal11                        # the start
build/graal-1.1-19990214/Graal11 --level levels/level1.graal --window
build/graal-1.1-19990214/Graal11 --server HOST:14802 --nick NAME
```
