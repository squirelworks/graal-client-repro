# Graal 2.05 rev 2 (GNW03081)

The first rebuild of the classic Graal 2.05 rev 2 client in Delphi
(Object Pascal). It talks the 2.05 wire protocol and plays the offline
Training levels and online servers with NPCs, items, weapons, baddies, the
GS1 script engine and the level editor. It is still early: see "Not yet".

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

These zips hold no original Graal code, graphics, sounds or levels. The
client carries simple graphics of its own; put a 2.05 install you own next
to it, or point `--data DIR` at one, for the real tiles, ganis, heads and
bodies.

## What's new in v0.0.3

- The Windows program carries its original's own icon (the Graal head, taken from
  the original exe), so Explorer shows it as the original did.
- Stress tested before release: a long soak with several players walking
  between levels, others connecting and dropping again and again, and a
  level with 80 scripted NPCs, with no crash, error or memory growth.

## Downloads

| Zip | Runs on | Window |
|---|---|---|
| `…-linux.zip` | Linux x86-64 | X11 |
| `…-windows.zip` | Windows, 32-bit (as 2.05 itself was) | GDI |

Each zip has `Graal205` (the client) and the build's README. The test
programs are built and run on every release but no longer shipped.

On Windows the first start may show **"Windows protected your PC"**. That
is SmartScreen meeting an unsigned program it has not seen before, not a
virus warning. Either click **More info**, then **Run anyway** (once), or
unblock the zip before you extract it: right-click it, **Properties**,
tick **Unblock**, **OK**. Then nothing in the folder is asked about again.
See [Windows says "Windows protected your PC"](https://github.com/squirelworks/graal-delphi#windows-says-windows-protected-your-pc).

## Where to put your Graal files

The zip has no Graal files in it. Put yours in the same folder as
`Graal205` (on Windows `Graal205.exe`), in either of these ways:

- Unzip `graal-assets.zip` into that folder, so the folder holds
  `Graal205.exe` and `graal-assets/` side by side.
- Or copy the contents of a Graal 2.05 install into that folder:
  `levels/`, `sounds/`, `pics1.png`, `body.png`, `sprites.png` and the rest,
  laid out as the install has them.

```
Graal 2.05/
  Graal205.exe
  graal-assets/        (from graal-assets.zip)
    common/
    2.05r2/
```

The original `Graal.exe` is not needed. Only that folder is read, never
the folder above it. `--data DIR` points at another folder instead.

## Playing online

Press Start, type your account and password, then press Enter (or
Refresh) to get the server list from listserver.graal.in:14923. Pick a
server and press Connect. A `listserver.txt` next to the program (host on
the first line, port on the second) names another listserver.

## What works

- NPCs and the GS1 script engine, items, combat, signs, weapons and the
  bow, the Q item list, baddies, sound, the map, and the level editor.
- Names under NPC characters and other players, as 2.05 draws them.
- Checked side by side with the real 2.05 rev 2 under Wine through the
  Training levels, action by action:
  - the default look (head26, facing up), the intro signs with their key
    names and face glyph, and the status bar icons;
  - a chat line along the bottom (Tab, type, Enter), with your line shown
    over your head;
  - chests opened by walking up into them, the glove, and lifting;
  - throwing: one tile a tick, a falling arc with a shadow, and the object
    breaking into pieces;
  - hiding under a carried bush or stone with D;
  - a heart and the hearts left over a character that was hit;
  - the next level drawn past the board's edge, as the real client scrolls
    into it;
  - the baddy, and the bomb's fuse and blast.
- Checked side by side with the real 2.05 rev 2 under Wine on the
  Training level: characters, heads, shields and shadows match.
- Login to a 2.05 server (gen-3 cipher, zlib framing, the 2.05 login line).
- The board, the player and other players drawn from the install's tiles
  and ganis; the 2.05 sprite prop and its poses (idle and walk so far).
- Walking and collision as 2.05 does it, and the player props sent back.
- Level links and warps. The point 2.05 tests for a link was measured on
  the real client under Wine: the body's centre pushed 1 to 1.5 tiles ahead
  in the walking direction.
- A start screen of its own when run with no arguments: Training for the offline levels, Start for the server list from
  the listserver (named in `listserver.txt`), then account and password.
  On Windows it is a windowed program.
- Its own small set of original built-in graphics and two offline levels,
  so it runs with nothing next to it. Files from a 2.05 install next to it,
  or under `--data`, replace them.
- A headless mode for stress runs, with a random walker, JSON stats and
  clean shutdown on SIGTERM / Ctrl+C. Twenty of these ran next to 92 bots on
  seihai-gserver for 60 s: all ended clean, 134 of 135 links went through,
  about 4.7 MB each.

## Running it

```
Graal205                                                   # start screen
GRAAL_PW=... Graal205 --server HOST:PORT --account NAME --data /path/to/graal205
Graal205 --level some.nw --data /path/to/graal205          # offline
Graal205 --server HOST:PORT --account NAME --headless --seconds 600 \
  --walk random --link-every 5 --stats-every 10              # stress run
```

Arrow keys or I/J/K/L walk, Esc leaves the game. Run `Graal205 --help` for
every flag.

## Not yet

Names and chat in the Windows system font (this build uses its own pixel
font); the Options page; UDP peer traffic; parts of
GS1 that print "not modelled" in the log. See the build's README for the full list.

## Checks behind this release

The test suite (265 checks) runs with range and overflow checks and the heap
tracer, and must end with no unfreed memory. It includes a fuzz run of
20000 random and mangled messages and 3000 random frames through the
receive path. CI also logs two of these clients into seihai-gserver, has the
second see the first, and walks one through a level link.
