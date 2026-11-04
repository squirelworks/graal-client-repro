# Graal 2.05 rev 2 (GNW03081)

The first rebuild of the classic Graal 2.05 rev 2 client in Delphi
(Object Pascal). It talks the 2.05 wire protocol, draws the board and the
players, walks, and takes level links. It is an early version: most of the
game (NPCs, items, weapons, the script engine, the editors) is not there yet.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

These zips hold no original Graal code, graphics, sounds or levels. Point the
client at a 2.05 install you own with `--data DIR` for the tiles, ganis,
heads and bodies.

## Downloads

| Zip | Runs on | Window |
|---|---|---|
| `…-linux.zip` | Linux x86-64 | X11 |
| `…-windows.zip` | Windows, 32-bit (as 2.05 itself was) | GDI |
| `…-macos.zip` | macOS on Apple silicon | none yet: headless, or `--dump` frames to a file |

Each zip has `Graal205` (the client), `Test205` (its test suite) and the
build's README. On macOS the binaries are not signed: after unzipping, run
`xattr -d com.apple.quarantine Graal205 Test205` once, or allow them under
System Settings > Privacy & Security.

## What works

- Login to a 2.05 server (gen-3 cipher, zlib framing, the 2.05 login line).
- The board, the player and other players drawn from the install's tiles
  and ganis; the 2.05 sprite prop and its poses (idle and walk so far).
- Walking and collision as 2.05 does it, and the player props sent back.
- Level links and warps. The point 2.05 tests for a link was measured on
  the real client under Wine: the body's centre pushed 1 to 1.5 tiles ahead
  in the walking direction.
- A headless mode for stress runs, with a random walker, JSON stats and
  clean shutdown on SIGTERM / Ctrl+C. Twenty of these ran next to 92 bots on
  seihai-gserver for 60 s: all ended clean, 134 of 135 links went through,
  about 4.7 MB each.

## Running it

```
GRAAL_PW=... Graal205 --server HOST:PORT --account NAME --data /path/to/graal205
Graal205 --level some.nw --data /path/to/graal205          # offline
Graal205 --server HOST:PORT --account NAME --headless --seconds 600 \
  --walk random --link-every 5 --stats-every 10              # stress run
```

Arrow keys or I/J/K/L walk, Esc quits. Run `Graal205` with no arguments for
every flag.

## Not yet

NPCs, baddies, items and weapons; the GS1 script engine; the editors; chat
bubbles and names; poses beyond idle and walk; the listserver step; UDP peer
traffic; a macOS window. See the build's README for the full list.

## Checks behind this release

The test suite (73 checks) runs with range and overflow checks and the heap
tracer, and must end with no unfreed memory. It includes a fuzz run of
20000 random and mangled messages and 3000 random frames through the
receive path. CI also logs two of these clients into seihai-gserver, has the
second see the first, and walks one through a level link.
