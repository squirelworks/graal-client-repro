# 15th Graal (V1.1) (19990125)

The first rebuild of the 15th Graal (V1.1) Graal client from 1998, in Delphi
(Object Pascal). Like the original it has no accounts: it joins a relay
server's game and plays with whoever is on the same level.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

These zips hold no original Graal code, graphics, sounds or levels. The
program carries small default graphics and a starter level of its own, so
it runs as it is. Put it in a folder with your own copy of this build's
files (or point it at one with `--data DIR`) and its tiles and levels take
their place.

On Windows the first start may show **"Windows protected your PC"**. That
is SmartScreen meeting an unsigned program it has not seen before, not a
virus warning. Either click **More info**, then **Run anyway** (once), or
unblock the zip before you extract it: right-click it, **Properties**,
tick **Unblock**, **OK**. Then nothing in the folder is asked about again.
See [Windows says "Windows protected your PC"](https://github.com/squirelworks/graal-delphi#windows-says-windows-protected-your-pc).

## What's new in v0.0.4

- Rebuilt from the latest code; the changes for this client are listed here as they land.

## What's new in v0.0.3

- The Windows program carries its original's own icon (the sword, taken from
  the original exe), so Explorer shows it as the original did.
- Stress tested before release: a long soak with several players on one
  relay and others connecting and dropping again and again, with no crash,
  error or memory growth.

## What works

- The start screen: nick name, Training, and Start with the relay server
  to join.
- Offline play on this build's levels: walking and collision.
- Online play through a relay server: two connections as the original
  opens, the room for the current level, pairing with the other players,
  the state sent to each new partner, and walking seen both ways.

## Not yet

Chat, items, weapons, enemies, level scripts, signs, saving, sound, and
the build's own character graphics (a stand-in character is drawn). This
is an early version: the comparison with the original, action by action,
comes later.

## Running it

Start `GraalB15` with no arguments for the start screen. From a
terminal: `GraalB15 --level levels/level1.graal --window`, or
`GraalB15 --server HOST:PORT --nick NAME`. `--help` lists every flag.
