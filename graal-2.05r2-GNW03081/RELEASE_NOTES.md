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

## Downloads

| Zip | Runs on | Window |
|---|---|---|
| `…-linux.zip` | Linux x86-64 | X11 |
| `…-windows.zip` | Windows, 32-bit (as 2.05 itself was) | GDI |

Each zip has `Graal205` (the client), `Test205` (its test suite) and the
build's README.

## What works

- NPCs and the GS1 script engine, items, combat, signs, weapons and the
  bow, the Q item list, baddies, sound, the map, and the level editor.
- Names under NPC characters and other players, as 2.05 draws them.
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

Chat bubbles; the Options page; UDP peer traffic; parts of
GS1 that print "not modelled" in the log. See the build's README for the full list.

## Checks behind this release

The test suite (264 checks) runs with range and overflow checks and the heap
tracer, and must end with no unfreed memory. It includes a fuzz run of
20000 random and mangled messages and 3000 random frames through the
receive path. CI also logs two of these clients into seihai-gserver, has the
second see the first, and walks one through a level link.
