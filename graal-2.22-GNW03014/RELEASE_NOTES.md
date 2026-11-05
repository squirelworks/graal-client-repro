# Graal 2.22 (GNW03014)

A rebuild of the classic Graal 2.22 client in Delphi (Object
Pascal). Like the original it is a windowed program: it opens on a start
screen with Training (the offline tutorial), the server list from the
listserver, and login. It talks the 2.22 wire protocol (gen 5: a compression byte per
frame, zlib or bzip2, and the partial XOR cipher), draws levels and gmaps,
walks across gmap edges, and takes level links. It also carries the
game layer of the 2.05 rebuild: the sword, lifting and throwing, chests,
items, combat and bombs, the status display, signs, weapons, level NPCs
with the GS1 script engine, baddies, sound effects and the maps. It is an
early version: 2.22's own additions to the script engine, the editors and
chat are not there yet.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

These zips hold no original Graal code, graphics, sounds or levels. The
program carries small original default graphics and a starter level of its
own, so it runs as it is. Put it in a 2.22 install you own (or point it at
one with `--data DIR`) and the install's tiles, ganis, heads, bodies,
start-window picture and offline tutorial take their place.

Files are looked for in the program's own folder first, then in
`graal-assets/2.22` and `graal-assets/common` beside it, then in the
`--data` folder. Nothing above the program's folder is read.

## Downloads

| Zip | Runs on | Window |
|---|---|---|
| `…-linux.zip` | Linux x86-64 | X11 |
| `…-windows.zip` | Windows, 32-bit (as 2.22 itself was) | GDI |

Each zip has `Graal222` (the client) and the build's README. The test
programs are built and run on every release but no longer shipped.

On Windows the first start may show **"Windows protected your PC"**. That
is SmartScreen meeting an unsigned program it has not seen before, not a
virus warning. Either click **More info**, then **Run anyway** (once), or
unblock the zip before you extract it: right-click it, **Properties**,
tick **Unblock**, **OK**. Then nothing in the folder is asked about again.
See [Windows says "Windows protected your PC"](https://github.com/squirelworks/graal-delphi#windows-says-windows-protected-your-pc).

## What works

- The start screen: nick name, Training, Start. Start fetches the server
  list (hosts from the install's `arrays2.dat`, or `listserver.txt` next
  to the program, else `listserver.graal.in:14922`), then account,
  password and Connect. When no listserver answers, the status line
  names each host that failed and why.
- Training: the offline tutorial levels, when they lie next to the
  program, with the tutorial's own tile set; else a built-in starter level.
- Login to a 2.22 server: login type 5, `GNW03014`, the tamper check, and
  gen-5 frames both ways. Checked against frames of a real 2.22 session:
  the rebuild makes the real client's uncompressed frames byte for byte
  and reads the real server's, bzip2 included.
- The 2.1+ player props (GANI as text, OSTYPE, TEXTCODEPAGE, gmap cells),
  stopping where 2.22's own parsers stop.
- The board, the player and other players drawn from the install's tiles
  and ganis.
- Walking and collision, with props sent every 100 ms as 2.22 does.
- S sword, A lift / throw / open, D weapon, Q item list, M map; items,
  bombs, hearts, death and respawn; signs.
- Level NPCs and their GS1 scripts, and baddies: offline from the level
  file (the offline tutorial's teacher, trees and cauldron), online from
  the server.
- Sound effects in a window (`--nosound` turns them off).
- Level links, asked with LEVELWARP or, for a level already seen,
  LEVELWARPMOD with its mod time, each followed by the tamper check.
- The ground of new-world maps: a level with a height grid in its
  `.gmap` is drawn as water, sand, sand and grass, or grass by height,
  with slopes lit from the upper left, as measured on the real 2.22.
- Baddies by 2.22's rules: they hunt the nearest player in the level,
  slide along walls, play 2.22's sounds (steps, frog, shield, splash,
  death), and a shield block pushes the player back.
- Gmaps: the warp onto a gmap, the `.gmap` file, the neighbouring levels,
  and walking over an edge into the next level.
- A headless mode for stress runs, with a random walker, JSON stats and
  clean shutdown on SIGTERM / Ctrl+C. Fifty of these ran in one level of
  seihai-gserver for 40 s: all ended clean, 1616 of 1619 links went
  through, about 4.8 MB each.

## Running it

Start `Graal222` with no arguments for the start screen. From a terminal:

```
GRAAL_PW=... Graal222 --server HOST:PORT --account NAME --data /path/to/graal222
Graal222 --level some.nw --data /path/to/graal222          # offline
Graal222 --level world.gmap --data /path/to/graal222       # offline gmap
Graal222 --server HOST:PORT --account NAME --headless --seconds 600 \
  --walk random --link-every 5 --stats-every 10              # stress run
```

Arrow keys or I/J/K/L walk, S sword, A lift / throw / open, D weapon,
Q item list, M map; Esc leaves the game (back to the start screen
when it was started from there). Run `Graal222 --help` for every flag.

## Not yet

2.22's additions to GS1 and its NPC props past 40; NPCs in gmap cells
other than the player's; the editors; chat bubbles, names and the chat
bar; Options; UDP peer traffic; macOS. See the build's README for the full list.

## Checks behind this release

The test suites (327 checks) run with range and overflow checks and the heap
tracer, and must end with no unfreed memory. It includes frames of a real
2.22 session, a bzip2 round trip against random and repetitive data, and a
fuzz run of 20000 random messages and 3000 random gen-5 frames through the
receive path. CI also logs two of these clients into seihai-gserver, has
the second see the first, and walks one through a level link.
