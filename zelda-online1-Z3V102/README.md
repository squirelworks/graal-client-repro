# Zelda Online 1 (`Z3-V1.02`)

Zelda Online 1 (May 1998), rebuilt. The original is a single-player Java 1.0
applet by Stefan Knorr, shown at scale 2 in a 512x448 box. It reads
`Z3-V1.02` and `Z3-V1.03` levels and starts on `level1.zelda`. It has no
network code. Graal later grew out of this game and its level editor.

This build is written in Java, like the original, and targets Java 8 class
files, so any Java 8 or newer runs it. It uses only AWT, as the applet did.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

No original code, graphics or levels are in this folder. The code is
written from the notes below, never from the original classes or from
decompiler output of them.

## Folder name

There is no version token in 1998, so the folder carries the level format
this build introduced: `Z3-V1.02` (11-bit board codes).

## Sources

| Area | Notes in [graal_analysis](https://github.com/squirelworks/graal_analysis) |
|---|---|
| What the applet is, start level, files it fetches | `client-internals/precursors-and-fan-builds.md` |
| Board bit stream, links, baddies, signs | `formats/level-binary.md` |
| Sign alphabet | `formats/sign-text.md` |
| `arrays.dat` | `client-internals/precursors-and-fan-builds.md` ("Shared Java game data") |
| Tick, walk step, corner slide, push timing | `client-internals/precursor-runs-2026-10-30.md` |

The tile sheet layout (`pics1.gif`, 512x256, four 128-pixel columns of 8x8
tiles) was read from the sheet itself and checked by drawing real levels.

## Classes

| Class | What it does |
|---|---|
| `Level` | `.zelda` reader: 11- and 12-bit board codes, single and double runs, links, baddies, signs |
| `SignText` | the sign alphabet |
| `Arrays` | `arrays.dat` reader; the first array is the walkable tiles |
| `Assets` | where files are found (below) |
| `StandIn` | the rebuild's own stand-in tiles and two small levels, drawn in code |
| `TileSheet` | where a tile sits on `pics1.gif` |
| `Game` | the 50 ms tick: walking, collision, corner slide, push counter, links, signs |
| `Renderer` | the 256x224 view, drawn at scale 2 |
| `ZeldaOnline1` | the window, and a headless scripted mode for tests |

## Build, test, run

```
zelda-online1-Z3V102/build.sh          # needs a JDK (11 or newer to build)
java -jar build/zelda-online1-Z3V102/ZeldaOnline1.jar
```

Arrow keys walk. Walk up into a sign to read it; Space, Enter, A or any new
direction closes it. `--data DIR` reads files from another folder,
`--level NAME` starts on another level, and `--keys rrdd.. --dump f.png`
runs headless, one key per tick, and writes the last frame.

`ZO1_DATA=dir` makes the test program also decode every `.zelda` file in
that folder.

## Where the files go

The jar lives in its folder and finds its files from there:

```
Zelda Online/
  ZeldaOnline1.jar
  graal-assets/zelda-online1/   (from the assets zip)
    pics1.gif  arrays.dat  levels/*.zelda
```

It looks in `--data`, then the jar's folder (and its `levels/`), then
`graal-assets/zelda-online1/`, then `graal-assets/common/`, and else uses
its stand-ins. Nothing above the jar's folder is read. The applet's files
can also simply sit next to the jar, as they sat next to the applet.

`make_assets.py SRC OUT.zip` makes the assets zip from your own copy. It
takes only `pics1.gif`, `arrays.dat` and the levels.

## What works (0.0.1)

- The title screen and HUD as measured (Mirae lab, 2026-11-13): "Press any
  key to start!" from x 121 on rows 370-382 of the 512x448 box, the logo
  from (100, 76). Any key leaves it, a click does not. The HUD, unscaled:
  picture at (20, 12), magic fill 8x8 at (24, 47), counters "000 / 00 /
  05" from x 65, 97 and 121 on rows 24-29, hearts at x 162, 170 and 178.
  `--title` shows the title in a scripted run.
- The start at (23, 37) on `level1.zelda`, view origin (64, 192).
- The window, 512x448, the board drawn from `pics1.gif` or the stand-ins.
- Levels: `Z3-V1.02` and `Z3-V1.03`, links (keep-coordinate arrivals
  included), baddy records, signs. All 51 `Z3-V1.03` levels of the Zelda
  Online 2 package decode.
- Walking at half a tile per 50 ms tick, collision from `arrays.dat`, the
  corner slide, the push counter (pose from tick 18, loop at 38).
- Level links and signs.

## Not yet

- [ ] The player sprite from `link.gif` (a stand-in figure is drawn).
- [ ] The sword, bushes and lifting.
- [ ] Baddies moving.
- [ ] Chests and the story flags.
- [ ] The password save.
- [ ] Sound.
- [ ] The title logo and the HUD picture: the originals' pictures are not
  here, so plain stand-ins are drawn in their places.
- [ ] The HUD counting anything (nothing changed it in the lab run).
- [ ] The soldier on `level1.zelda`: it starts at about (18, 48) and moves
  in straight runs with pauses (down, up, a pause, right about 90 pixels,
  a pause, then down); the rebuild does not move baddies yet.
