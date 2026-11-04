# Zelda Online 1

A rebuild of Zelda Online 1 (May 1998), the single-player Java game that
Graal grew out of. It is written in Java, as the original was, and runs on
any Java 8 or newer. This is a first, early release.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

The zip holds no original code, graphics or levels. The game carries simple
stand-in graphics and two small levels of its own, so it runs with nothing
next to it.

## Running it

Unzip, then double-click `ZeldaOnline1.jar` or run
`java -jar ZeldaOnline1.jar`. Arrow keys walk. Walk up into a sign to read
it.

## Your own files

Put your Zelda Online files in the same folder as the jar:

- run `make_assets.py` on your copy (`python3 make_assets.py SRC assets.zip`)
  and unzip the result next to the jar, so the folder holds
  `ZeldaOnline1.jar` and `graal-assets/` side by side;
- or copy `pics1.gif`, `arrays.dat` and the `.zelda` levels next to the jar.

## What works

- The board and levels (`Z3-V1.02` and `Z3-V1.03`), level links and signs.
- Walking, collision and the corner slide at the original speed, and the
  push pose against walls.

## Not yet

The real player sprite, the sword, bushes, baddies, chests, the password
save and sound.
