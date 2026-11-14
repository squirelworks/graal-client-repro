# Java Graal (2000)

Java Graal, rebuilt. The original is a Java 1.1 applet (512x418) that
Cyberjoueur served on its site in July 2000, next to their other Java games.
In code terms it is Zelda Online 2's game and client with Graal art
(`pics1.gif`, `sprites.gif`, `letters.gif`) and Graal levels. It opens on
a title screen, starts on `level13.graal` at (20.5, 38), has no start
window, and joins the relay on its own host's port 14802, one room per
level.

This build is written in Java, like the original, and targets Java 8 class
files, so any Java 8 or newer runs it. It uses only AWT.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

No original code, graphics or levels are in this folder. The code is
written from the notes below, never from the original classes or from
decompiler output of them.

## Folder name

The applet sends no version token and has no version number of its own,
so the folder carries the year: `javagraal-2000`.

## Sources

| Area | Notes in [graal_analysis](https://github.com/squirelworks/graal_analysis) |
|---|---|
| What the applet is, start level, host and port, room prefix, D set | `client-internals/precursors-and-fan-builds.md` |
| Lobby lines, D payloads, level leader | `protocol/relay-1998.md` |
| Level formats it reads, NPC images, chests skipped | `formats/level-binary.md`, `client-internals/precursors-and-fan-builds.md` |
| Sign alphabet | `formats/sign-text.md` |
| Tick, walking, push timing, chat drawing | `client-internals/precursor-runs-2026-10-30.md` |

## Classes

| Class | What it does |
|---|---|
| `javagraal.JavaGraal` | the applet's 512x418 box in a window, chat line, headless mode |
| `javagraal.Net` | relay client: room `G2` + level name, party on the first `+`, state push on `P`, D types with `L` and without `S`, the `nickname:` chat command, level leader |
| `javagraal.Level` | `Z3-V1.03`, `Z3-V1.04`, `GR-V1.00` to `GR-V1.03`: 12- and 13-bit boards, links, baddies with verses, NPC images (`.gif` added), chests skipped, signs |
| `javagraal.Renderer` | the board at 16 pixels a tile (8-pixel sheets doubled), NPC images, players, chat and names without a bubble |
| `javagraal.Game`, `Relay`, `Assets`, `StandIn`, `TileSheet`, `Arrays`, `SignText`, `Colours` | as in the Zelda Online 2 rebuild, own copies |
| `gserv.GServ` | a relay lobby for local play, on 14802 |

## Build, test, run

```
javagraal-2000/build.sh                          # needs a JDK (11 or newer to build)
java -jar build/javagraal-2000/GServ.jar         # a relay, port 14802
java -jar build/javagraal-2000/JavaGraal.jar --host 127.0.0.1
```

With no `--host` it tries `listserver.graal.in:14802`, the stand-in for
the site the applet was loaded from, and plays alone if no relay answers.
`--offline` skips the relay. Arrow keys walk, Enter opens the chat line,
`nickname: NAME` in chat sets the nickname. `--keys rrdd.. --dump f.png`
runs headless. `JG_DATA=dir` makes the test program also decode every
level in that folder.

## Where the files go

The jars live in their folder and find their files from there:

```
Java Graal/
  JavaGraal.jar  GServ.jar
  graal-assets/javagraal/      (from the assets zip)
    pics1.gif  sprites.gif  letters.gif  arrays.dat  levels/
```

It looks in `--data`, then the jar's folder (and its `levels/`), then
`graal-assets/javagraal/`, then `graal-assets/common/`, and else uses its
stand-ins. `make_assets.py SRC OUT.zip` makes the assets zip from your own
copy: the four top files plus the levels and the GIFs and sounds in
`levels/`.

## What works (0.0.1)

- The title screen as measured (isolated lab, 2026-11-13): black, the logo
  box at (100, 130), "Press any key to start!" from x 151. Letters,
  digits, Space and the arrows leave it; Enter, Esc, Tab, Shift, F1 and
  clicks do not, and the key that leaves it does nothing in the game.
  `--title` shows it in a scripted run.
- The start at (20.5, 38) on `level13.graal`, with the view centred on
  the 32x32 body in the 512x384 board view (origin (88, 432)), and the
  chat field in the 30 rows from y 386.
- The window, the board from `pics1.gif` (16-pixel Graal sheets and
  8-pixel Zelda Online sheets), NPC images from the levels.
- Levels: all formats above; 206 levels of an early Delphi Graal install
  (`GR-V1.00` to `1.02` and `Z3-V1.04`) decode and `level13.graal` draws as
  expected.
- Walking, collision, corner slide and push timing, links, signs.
- Multiplayer through the relay: players on the same level see each
  other's position, nickname, chat and level name.

## Not yet

- [ ] The player sprite from `sprites.gif` (a stand-in figure is drawn).
- [ ] Sword, bushes, baddies, chests.
- [ ] Board changes over the wire.
- [ ] Sound.
- [ ] The full tile-type table: whether the walkable-tile list in a Graal
  `arrays.dat` is read the same way as Zelda Online's has only been
  checked by walking.
- [ ] The title screen's logo: the original's picture is not here, so an
  outline and the name stand in for it.
- [ ] Whether the view stops at the board's edges (the lab runs did not
  reach one; the rebuild clamps).
