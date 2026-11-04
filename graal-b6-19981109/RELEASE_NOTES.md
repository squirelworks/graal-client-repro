# 6th Graal (beta5) (19981109)

The first rebuild of the 6th Graal (beta5) Graal client from 1998, in Delphi
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

Start `GraalB6` with no arguments for the start screen. From a
terminal: `GraalB6 --level levels/level1.graal --window`, or
`GraalB6 --server HOST:PORT --nick NAME`. `--help` lists every flag.
