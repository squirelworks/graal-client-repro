# Java Graal

A rebuild of Java Graal, the Graal applet that ran in web browsers in
2000. It is written in Java, as the original was, and runs on any Java 8
or newer. This is a first, early release.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

The zip holds no original code, graphics or levels. The game carries simple
stand-in graphics and two small levels of its own, so it runs with nothing
next to it.

## What's new in v0.0.3

- Faithfulness pass: compared side by side with the original program it was
  rebuilt from, and the differences found brought in line with it.

## Running it

Unzip, then run `java -jar JavaGraal.jar` (or double-click it). It starts
on `level13.graal` and looks for a relay to meet other players; with none
it plays alone.

To play together on your own network, start `java -jar GServ.jar` on one
machine (port 14802) and run `java -jar JavaGraal.jar --host ADDRESS` on
each player's machine. Players meet when they are on the same level.

Arrow keys walk. Enter opens the chat line; `nickname: NAME` sets your
name.

## Your own files

Put your Java Graal files in the same folder as the jars:

- run `make_assets.py` on your copy (`python3 make_assets.py SRC assets.zip`)
  and unzip the result next to the jars;
- or copy `pics1.gif`, `sprites.gif`, `letters.gif`, `arrays.dat` and the
  `levels/` folder next to them.

## What works

- The Graal levels with their tiles and NPC pictures, level links and signs.
- Walking and collision at the original speed.
- Seeing other players on the same level, with their names and chat.

## Not yet

The real player sprite, the sword, bushes, baddies, chests and sound.
