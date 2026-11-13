# Graal Adventure Demo, Game Boy Color

The first rebuild of the 1999 Graal Adventure Demo for the Game Boy Color,
written in C with GBDK as the original was. It opens straight into the
first room, as the demo did, and plays its seven rooms: walking, signs and
people to talk to, the Select menu over all 31 characters, the sword, lifting
and throwing bushes and stones, the bomb and the boomerang, the patrolling
and chasing soldiers, and the captive who shows how to lift a bush.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

This zip holds no original Graal code, graphics, rooms or text. The ROM
carries simple art and rooms of its own, so it runs as it is. With a copy
of the demo that you own, `import_assets.py` makes a second ROM that shows
the demo's own graphics, rooms and texts.

## What's new in v0.0.5

- Rebuilt and released together with every other client; no changes to this client since v0.0.4.

## What's new in v0.0.4

- Rebuilt from the latest code; the changes for this client are listed here as they land.

## What's new in v0.0.3

- Rebuilt and released together with every other client.

## Downloads

One zip, `graalgb-1.10-….zip`, the same on every system:

| File | What |
|---|---|
| `GraalGB.gbc` | the ROM; runs in any Game Boy Color emulator or on a flash cartridge |
| `import_assets.py`, `gpak.py` | make `GraalGB-original.gbc` from your copy of the demo |
| `README.md` | the build's README |

## With the original graphics

Put your copy of the demo (a 262,144-byte `.gb` or `.gbc`, found by its
MD5, whatever its name) next to `GraalGB.gbc`, or in `graal-assets/gb-1.10/`
inside that folder, and run `python3 import_assets.py` there (Python 3, no
other packages). It writes `GraalGB-original.gbc` next to it.

## Controls

D-pad walks and turns the text pages; B swings the sword; A lifts and
throws, drops a bomb or throws the boomerang, depending on the character;
Select opens the character menu (left and right pick); Start turns the
sound off, as in the demo.

## Not yet

People are drawn with this rebuild's own bodies even with the original
graphics; carried things, the bomb and the boomerang use their own
sprites; some timings (room loads, the captive's steps) are close but not
exact. A Game Boy Color is needed.

## Checks behind this release

The ROM is built on Linux and Windows. An emulator test plays it through
the start, walking, both directions of a room link, a sign, the sword, the
menu, lifting and throwing, the captive's show and every room. With the
original's assets, the first room, the text box and the menu were compared
with the demo by eye, and walking traces were compared with the demo's
position by position.
