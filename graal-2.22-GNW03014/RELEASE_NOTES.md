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
early version: 2.22's own additions to the script engine and the editors
are not there yet.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

The program carries what 2.22's own `Graal_222.exe` carries: the start
window and server list art and buttons, the nine Training levels, the
English words of its windows and the Graal head icon. It also carries the
2.22 install's art that the start screen and Training use: the tiles
(`pics1.png`, `picso.png`), the sprites, status and letters pictures, the
bombs, `arrays.dat`, the name font, the offline tutorial map with its
levels, ganis and pictures, and the default body, head, sword and shield.
So it runs on its own, with nothing beside it, and looks like 2.22. Put
it in a 2.22 install (or point it at one with `--data DIR`) and it uses
what that install holds first.

Files are looked for in the program's own folder first, then in
`graal-assets/2.22` and `graal-assets/common` beside it, then in the
`--data` folder. Nothing above the program's folder is read.

## What's new in v0.0.5

- [x] **Minimap only on the map.** The minimap is drawn only on a level of its grid, as the real client does: a server's level off the map (or a house or cave) shows none. Before, it was drawn on every level.
- [x] **Chests from the server are drawn.** A chest that arrives only as `PLO_LEVELCHEST` (4), on a board with no chest tiles, is drawn closed, and one sent as already opened is drawn opened, as the real client does (lab run 2026-11-12). Before, it blocked the player and could be opened but stayed invisible until then.
- [x] **F1 Help window.** F1 opens "Help" from the build's own form (TOptions): the "Game windows" group and Close. It is a real dialog on Windows and drawn elsewhere. The rebuild has no editor in 2.22 yet, so Edit level closes it like the other buttons, which do nothing yet.
- [x] **Neutral window titles.** The server list window is titled "Server List", not the original's caption, which named the original's host (#191).
- [x] **Walking in Training.** The tutorial's `addtiledef picso.png,offlinetutorial,1` now keeps its sheet type, and a type 1 or 2 sheet tells walls from the tile number (the newer tile order) instead of from `arrays.dat`, whose lists hold none of the tutorial's ground. The player could only turn on the spot before.

- [x] **The chat line.** Tab gives the keys to the white line under the game and back; Enter says what is typed, and what each player says is drawn over the head (in `TEMPSITC.TTF` when the install has it).

- [x] **System weapons stay out of Q.** A weapon whose name starts with `-` (the Reborn server's `-gr_movement`) runs but is not shown in the item list.

- [x] **Pictures by kind.** The picture cache keeps each name once per kind (head, body, sword, shield, hat, weapon), because each kind searches its own folders. A picture first asked for without its kind got the built-in stand-in and kept it, so an install's own picture could stay hidden behind the stand-in (in 1.33, `levels/weapons/wbomb1.gif` beside the D button).

## What's new in v0.0.4

- Rebuilt from the latest code; the changes for this client are listed here as they land.

## What's new in v0.0.3

- Stress tested before release: a long soak with several players walking
  between levels, others connecting and dropping again and again, and a
  level with 80 scripted NPCs, with no crash, error or memory growth.

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
See [Windows says "Windows protected your PC"](https://github.com/squirelworks/graal-client-repro#windows-says-windows-protected-your-pc).

## What works

- 2.22's own start window, in a 577 x 416 window of its own with only a
  close button: the art and buttons of `Graal_222.exe`,
  Nickname, Language, Account and Password laid out as the original's
  form, the words from `languages/languageEnglish.txt`, and the nickname
  and last account 2.22 saved in the registry. Start fetches the server
  list (hosts from the install's `arrays2.dat`, or `listserver.txt` next
  to the program, else `listserver.graal.in:14922`) and opens 2.22's
  server list: Gold, Silver and Bronze tabs, the server's language,
  version, description and homepage, the listserver's message, and
  Connect. The game then opens in its own 640 x 480 window titled
  "Graal: <server>". The windows have the original's frames, and the
  taskbar shows one Graal button with the Graal head.
- Alt+Enter switches to fullscreen and back, as 2.22 does: the screen
  goes to `fullscreenmode` from the install's `graalconfig.txt`
  (1024 x 768 when it has none) and more of the level is shown.
  `startinfullscreen=true`, or Shift held on Start or Training, starts
  the game in fullscreen.
- Training: the real offline tutorial with its nine levels, starting
  below the cauldron. The tutorial's script dresses the player as 2.22
  does (blond hair, brown shirt, shield) and puts in its own walking
  ganis. The lamps burn with their gani scripts (light and flame), and the
  teacher's "Touch to get information" sign floats over its arrow in the
  name font, at the size 2.22 draws gani movie text.
- Login to a 2.22 server: login type 5, `GNW03014`, the tamper check, and
  gen-5 frames both ways. Checked against frames of a real 2.22 session:
  the rebuild makes the real client's uncompressed frames byte for byte
  and reads the real server's, bzip2 included.
- The 2.1+ player props (GANI as text, OSTYPE, TEXTCODEPAGE, gmap cells),
  stopping where 2.22's own parsers stop.
- The board, the player and other players drawn from the install's tiles
  and ganis, with every head shown: a gani's default hat is not drawn
  over anyone. Bodies change only their key colours (skin, coat,
  sleeves, shoes, belt), so bodies drawn in other colours show as they
  are. Gani attributes `#P1` to `#P30`, pictures found in any folder of
  `levels/`.
- Server NPCs on gmaps: each in its own cell, the cells around the
  player drawn at their place on the map, and names under character
  NPCs in the install's `TEMPSITC.TTF`, white over dark blue.
- The sword and glove icons in the status display, and the white chat
  line under the play area.
- On Windows, the Graal head as the program's icon in the title bar and
  the taskbar.
- Walking and collision, with props sent every 100 ms as 2.22 does.
- S sword, A lift / throw / open, D weapon, Q item list, M map; items,
  bombs, hearts, death and respawn; signs.
- Level NPCs and their GS1 scripts, and baddies: offline from the level
  file (the offline tutorial's teacher, trees and cauldron), online from
  the server.
- Sound effects in a window (`--nosound` turns them off).
- Level links, asked with LEVELWARP or, for a level already seen,
  LEVELWARPMOD with its mod time, each followed by the tamper check.
- The ground of new-world maps, built as 2.22 builds it: the `.gmap`'s
  height field, its seeded random displacement and each level's HEIGHTS
  points give every tile corner a height. The ground tiles are picked
  from the corner heights as 2.22 picks them (water, sand, grass and the
  edges between, with its flowers, mushrooms and stones), each pixel is
  lit by the slope, and shallow water foams at the shore. It stands
  raised by its height: the ground, players and NPCs go up 16 px per
  height step, and the camera follows the player's raised place, so Training's hills and palms sit where 2.22 draws them.
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

Most of 2.22's additions to GS1; the account and language drop-downs,
Get an account!, Show More and Donations; the
editors; Options; UDP peer traffic; macOS. Gani movies advance one
frame per 50 ms game tick, a step not yet traced from `Graal_222.exe`.
See the build's README for the full list.

## Checks behind this release

The test suites (363 checks) run with range and overflow checks and the heap
tracer, and must end with no unfreed memory. It includes frames of a real
2.22 session, a bzip2 round trip against random and repetitive data, and a
fuzz run of 20000 random messages and 3000 random gen-5 frames through the
receive path. CI also logs two of these clients into seihai-gserver, has
the second see the first, and walks one through a level link.
