# 39ster's Graal client 1.00

A behavioural port of 39ster's Graal client 1.00 (April 2014), the offline
fan remake. The original is `GameMaker.exe`, a small C++ engine on SDL 1.2
with zlib and stb_image and the GameMonkey scripting language (unrelated to
YoYo's GameMaker), SHA-256
`ab47332b27479aa8c586da8daeaab0065a8adca80271de30a5d4fe694b3826cf`. All of
its Graal logic is in a game script it ships beside the engine.

It is not a Delphi Graal client and not one of the Torque builds, so this
folder is its own profile: nothing here is shared with the official
clients' game code beyond the level reader and the drawing surface in
`common/`. It is written in Object Pascal like the rest of the repository,
so it is a port of the behaviour, not of the original's language or
runtime. This is the 0.0.1 starting point: a viewer.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, Stéphane Portha ("unixmad"), or 39ster.

## Sources

From [graal_analysis](https://github.com/squirelworks/graal_analysis), not
from the original's script or engine:

| Area | Notes |
|---|---|
| What the client is, its files | `client-internals/precursors-and-fan-builds.md` (39ster's Graal client 1.00) |
| Start, drawing, tiles, collision, movement, controls, animation, links | `client-internals/precursor-mechanics-2026-11-09.md` (39ster's client mechanics, evidence `GRAAL39STER-ENGINE-20261109-01`) |
| GLEVNW01 levels | `formats/glevnw01.txt` |

The notes read the rules from the original's script and engine with thin
run-time checks: only the town render and pausing with `P` were run. The
numbers in `src/Profile39.pas` were not tested at run time on the
original, and this folder keeps that distinction.

## Units

| Unit | What |
|---|---|
| `src/Profile39.pas` | the profile: start level and position, view, sheet size, categories, facing order, the eight ganis and their frame counts, movement and animation constants, the time factor |
| `src/Tiles39.pas` | NW base64 pairs to 12-bit ids, ids to sheet cells (each 512-id block 16 columns across), the 10/10/12-bit packed tile, the category table and which categories are walls |
| `src/Camera39.pas` | the camera: centred on the 16-pixel anchor, clamped to the level, a smaller level centred |
| `src/World39.pas` | a level with the player's sheet and category table, drawn into a 640 x 480 frame |
| `src/Graal39ster.dpr` | the front end: the window, or one frame to a `.bmp` |

## Files it opens

Everything comes from the player's own 39ster install; no file of it is in
this repository or in the release zips. Looked for in the program's
folder, then `graal-assets/39ster/` and `graal-assets/common/` next to it,
then the folder given with `--data`:

- `levels/level13.nw` (or the level named with `--level`), and any
  `GLEVNW01` or `GR-V1.00`–`1.03` level under `levels/`;
- `pics1.png`, the tile sheet (128 x 32 cells of 16 pixels; without it the
  tiles are drawn as flat colours by category);
- `arrays.dat`, the category table: plain text, one letter per sheet cell,
  row by row, `A` for the first category in `Profile39`'s order (ground,
  blocking, throw-through, water, chair, jump, swamp, shallow water). The
  letter-to-category order follows the order the notes list the categories
  in; it agrees with where the install's own table puts water, chairs and
  swamp on the sheet, but the notes do not state it outright.

## Running it

```
Graal39ster                                   # in the install's folder
Graal39ster --data DIR                        # an install elsewhere
Graal39ster --level other.nw --x 100 --y 200  # another level and spot
Graal39ster --data DIR --frame out.bmp        # one frame, no window
```

It opens a 640 x 480 window on `level13.nw` with the anchor at (512, 512).
The arrow keys move the anchor 3 pixels a tick, with no collision yet; Esc
ends it.

## Building and testing

`scripts/build.sh graal-39ster-1.00`, then `scripts/test.sh`.
`tests/Test39ster.dpr` uses generated fixtures only (levels, category
tables and a tile sheet it makes itself) and reads nothing of the
original.

## Not yet

The slices of issue #176, in order:

- [x] An explicit independent profile, the source and run-time boundary,
  and player-supplied resource loading; no original script or art imported.
- [x] Generated NW and category fixtures: 64 x 64 boards, the sheet mapping
  across 512-id blocks and category-index interpretation.
- [ ] Generated character-piece rendering (body, head, shield, sword and
  attribute pieces). Viewport clamping and centring are done
  (`Camera39`); the player is a white box.
- [ ] Movement: cardinal and diagonal, the time factor from the previous
  frame, vertical before horizontal, the 1-unit shrink, single-axis slides
  and 16-pixel snapping, with asymmetric generated obstacles.
- [ ] Animation fixtures: looping walk, sword return, held pose, and frame
  commands (wait, sound) skipped; timing tested apart from names that
  suggest milliseconds.
- [ ] Pause, grab and pull, sign paging (3 lines, Up scrolls back) and
  release.
- [ ] Links between two generated rooms: kept axes, failed loads and the
  latch that stops repeat warps.
- [ ] NPCs show their images only; their scripts are not run, as in the
  original. No NPC or server engine is planned beyond that.
- [ ] No side-by-side run against the original yet. macOS only at polishing.
