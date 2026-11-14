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

## What's new in v0.0.5

- [x] A title screen, as the original's: "Press any key to start!" (the logo is a stand-in). Any key starts the game.
- [x] The HUD in the original's places: the magic bar, rupees, bombs and arrows (000 / 00 / 05) and three hearts, drawn with stand-ins.
- [x] The game starts where the original does on `level1.zelda`.

## What's new in v0.0.4.2

- Reads the shared asset root: in a folder holding `_clients/`, it takes `_clients/<label>/` first and then only the root files its `files.txt` names, never a file from another version's install (#192).

## What's new in v0.0.4

- Rebuilt from the latest code; the changes for this client are listed here as they land.

## What's new in v0.0.3

- Rebuilt and released together with every other client.

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
