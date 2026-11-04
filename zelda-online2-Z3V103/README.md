# Zelda Online 2 (`Z3-V1.03`)

Zelda Online 2, the "local version" of July 1998, rebuilt, together with the
GServ lobby it shipped with. The original is a Java 1.1 application by
Stefan Knorr: a start window with "One-Player mode" and "Multiplayer mode",
a server address field and the player's options, then the game in a
512x448 view. Multiplayer goes through GServ on port 14801, one lobby room
per level. It is the step between Zelda Online 1 and the first Delphi Graal.

This build is written in Java, like the original, and targets Java 8 class
files, so any Java 8 or newer runs it. It uses only AWT.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

No original code, graphics or levels are in this folder. The original
package includes its author's source; none of it was read for this build or
copied into it. The code is written from the notes below.

## Folder name

There is no version token in 1998, so the folder carries the level format
the game ships its levels in: `Z3-V1.03`.

## Sources

| Area | Notes in [graal_analysis](https://github.com/squirelworks/graal_analysis) |
|---|---|
| What the package is, start window, options, files | `client-internals/precursors-and-fan-builds.md` |
| GServ lines, ids, parties, room names | `client-internals/precursors-and-fan-builds.md` ("Network"), `protocol/relay-1998.md` |
| D payloads (P, C, N, S, T, O, I), sender id, number encoding, level leader | `protocol/relay-1998.md` |
| Tick, walking, push timing, chat and name drawing | `client-internals/precursor-runs-2026-10-30.md` |
| Board, links, baddies, signs | `formats/level-binary.md`, `formats/sign-text.md` |

## Classes

| Class | What it does |
|---|---|
| `zo2.ZeldaOnline2` | start window (modes, address, nickname, own name, colours), game window, chat line, headless mode |
| `zo2.Net` | the game's side of the lobby: room per level, party on the first `+`, state push on `P`, D payloads, level leader |
| `zo2.Relay` | the text-line socket |
| `zo2.Game` | the 50 ms tick: walking, collision, corner slide, push counter, links, signs |
| `zo2.Renderer` | the view; chat and names as bold serif text with a white offset copy, no bubble |
| `zo2.Level`, `SignText`, `Arrays`, `Assets`, `StandIn`, `TileSheet`, `Colours` | files, stand-ins, tiles, colours |
| `gserv.GServ` | the lobby: ids, games, `N O S + - P C V D H` |

## Build, test, run

```
zelda-online2-Z3V103/build.sh                  # needs a JDK (11 or newer to build)
java -jar build/zelda-online2-Z3V103/GServ.jar # the lobby, port 14801
java -jar build/zelda-online2-Z3V103/ZeldaOnline2.jar
```

The address field is pre-filled with `listserver.graal.in`; type
`127.0.0.1` for a GServ on the same machine. Arrow keys walk, Enter opens
the chat line (multiplayer), Space or A reads a sign.

Flags: `--one-player`, `--server HOST[:PORT]`, `--nick NAME`, `--data DIR`,
`--level NAME`, `--keys rrdd.. --dump f.png` (headless). `ZO2_DATA=dir`
makes the test program also decode every `.zelda` in that folder.

## Where the files go

The jars live in their folder and find their files from there:

```
Zelda Online 2/
  ZeldaOnline2.jar  GServ.jar
  graal-assets/zelda-online2/   (from the assets zip)
    pics1.gif  arrays.dat  levels/*.zelda
```

It looks in `--data`, then the jar's folder (and its `levels/` and
`game/`), then `graal-assets/zelda-online2/`, then `graal-assets/common/`,
and else uses its stand-ins. The original package can also simply be
unpacked next to the jar. `make_assets.py SRC OUT.zip` makes the assets
zip from your own copy: `pics1.gif`, `arrays.dat` and the levels only.

## What works (0.0.1)

- The start window with both modes and the options; the game window.
- Levels, links, signs, walking, collision, corner slide and push timing.
- Multiplayer: room per level (`Zlevel11.6` for `level1.zelda`), party on
  the first `+`, the state push on `P`, positions every 2 ticks, chat,
  nickname, colours, leaving the room on a level change, the level leader.
- The GServ lobby. The rebuilt client was also run against the original
  GServ server on loopback: both players got ids, joined a party and saw
  each other's nickname and position.

## Not yet

The player sprite from `link.gif` (a stand-in figure is drawn, coloured by
the options), sword, bushes, lifting, baddies, chests, board changes over
the wire, the password save (its alphabet and mask are not in the notes
yet), sound. The colour list is the rebuild's own. The original start
position is not known; the rebuild starts near the middle of `level1`.
