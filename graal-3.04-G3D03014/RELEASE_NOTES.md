# Graal 3.04 for Linux (G3D03014)

A rebuild of the Graal 3.04 Linux client in Delphi (Object Pascal). The
original 3.04 is a C++ program on the Torque engine; on the wire it talks
the same protocol as the Windows 2.22 client, so this rebuild starts from
the 2.22 one and changes what 3.04 does differently. Since 0.0.2 it also
carries the 2.22 rebuild's game layer: NPCs and their GS1 scripts,
baddies, items, combat, sound, the maps, and the ground drawn from a
level's height grid. It is still an early version: chat, Options and the
UDP channel between players are not there yet.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

These zips hold no original Graal code, graphics, sounds or levels. The
program carries small original default graphics and a starter level of its
own, so it runs as it is. Put it in the root of a 3.04 install you own (or
point it at one with `--data DIR`) and the install's tiles, ganis, heads,
bodies, sounds and offline tutorial take their place.

Files are looked for in the program's own folder first, then in
`graal-assets/3.04` and `graal-assets/common` beside it, then in the
`--data` folder. Nothing above the program's folder is read.

## Downloads

| Zip | Runs on | Window |
|---|---|---|
| `…-linux.zip` | Linux x86-64 | X11 |
| `…-windows.zip` | Windows, 32-bit | GDI |

Each zip has `Graal304` (the client) and the build's README. The test
programs are built and run on every release but no longer shipped.

On Windows the first start may show **"Windows protected your PC"**. That
is SmartScreen meeting an unsigned program it has not seen before, not a
virus warning. The exe carries a version block and a manifest naming it
as graal-delphi, but it is not signed. Either click **More info**, then
**Run anyway** (once), or unblock the zip before you extract it:
right-click it, **Properties**, tick **Unblock**, **OK**. Then nothing in
the folder is asked about again.
See [Windows says "Windows protected your PC"](https://github.com/squirelworks/graal-delphi#windows-says-windows-protected-your-pc).

## New in 0.0.2

- **The game layer.** The sword (S), lifting and throwing (A), weapons
  (D), the item list (Q) and the map (M); items, bombs, hearts, death and
  respawn; chests and signs. Level NPCs run their GS1 scripts, offline
  from the level file (the tutorial's teacher, trees and cauldron) and
  online from the server.
- **Baddies** by 2.22's rules: they hunt the nearest player in the level,
  slide along walls, play their sounds, and a shield block pushes the
  player back.
- **Sound effects** from the install's `sounds/` folder (`--nosound` turns
  them off).
- **The ground** of a level with a height grid in its `.gmap` (such as
  3.04's `maps/offlinetutorial.gmap`): water, sand, sand and grass, or
  grass by height, with slopes lit from the upper left.
- **Training** starts on the tutorial below the cauldron, not inside it.
- **Assets** are found from the program's folder first (see above), so a
  `graal-assets/3.04` folder next to the program is enough.
- **The listserver.** `listserver.graal.in` is looked up by name on
  Windows too, so Start reaches it there. When no listserver answers, the
  status line names each host that failed and why. The two NUL bytes the
  public listserver puts after each frame no longer hide the status line.

## What works

- The start screen: nick name, Training, Start. Start fetches the server
  list from `listserver.graal.in` on port 14922 (or the host in
  `listserver.txt` next to the program); the hosts in the install's
  `license/license.graal` are tried after it. Then account, password and
  Connect.
- The 3.04 listserver login: id 7 (`G3D30123newmain`) and the account in
  one frame, the list back in gen 5.
- Login to a server as 3.04 does it: `G3D03014`, then the language and the
  two map files in the same first frame, and no tamper check, ever.
- The first props as 3.04 sends them (`linux`, code page 1250), and no
  periodic message over TCP.
- The board, the player and other players drawn from the install's tiles
  and ganis; walking and collision; level links; gmaps and their edges.
- The game layer, NPCs, baddies, sound and ground listed above.
- A headless mode for stress runs, with JSON stats.

## Running it

Start `Graal304` with no arguments for the start screen. From a terminal:

```
GRAAL_PW=... Graal304 --server HOST:PORT --account NAME --data /path/to/graal304
Graal304 --level some.nw --data /path/to/graal304          # offline
```

Arrow keys walk, S sword, A lift / throw / open, D weapon, Q item list,
M map; Esc leaves the game (back to the start screen when it was started
from there). Run `Graal304 --help` for every flag.

## Not yet

Chat; Options; the UDP channel between players; the profile and PM
windows; the list tabs (Gold, 3D, Hosted); the `GSERVL01` level format;
checking the licence file's signature; 2.22's additions to GS1. The play
layer is 2.22's: what the 3.04 engine does differently in play has not
been checked against the real 3.04 yet. See the build's README for the
full list.

## Checks behind this release

The test suites (327 checks) run with range and overflow checks and the
heap tracer, and must end with no unfreed memory. CI also logs two of
these clients into seihai-gserver, has the second see the first, and
walks one through a level link.

Before release the Linux build was started with no arguments next to a
`graal-assets/3.04` folder: the start screen opened, Training opened the
tutorial with its NPCs and ground, Esc went back, and Start's server list
named each listserver it tried.
