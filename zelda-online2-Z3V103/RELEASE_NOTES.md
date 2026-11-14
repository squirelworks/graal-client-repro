# Zelda Online 2

A rebuild of Zelda Online 2 (July 1998) and the GServ lobby it came with:
the Java game that took Zelda Online multiplayer. It is written in Java, as
the original was, and runs on any Java 8 or newer. This is a first, early
release.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

The zip holds no original code, graphics or levels. The game carries simple
stand-in graphics and two small levels of its own, so it runs with nothing
next to it.

## What's new in v0.0.5

- [x] The server field starts at loopback (127.0.0.1) with One-Player mode selected. Multiplayer needs a server you choose.

- [x] The start window is laid out as the original's "Zelda Start": the two modes, the server address, Play and Cancel. Nickname, colours and showing your own name moved to an Options button under the game, as in the original.
- [x] The game opens on a title screen ("Press any key to start!") and shows the original's HUD places (magic, rupees, bombs, arrows, three hearts), drawn with stand-ins.
- [x] Chat is typed in a field under the game.

## What's new in v0.0.4.2

- Reads the shared asset root: in a folder holding `_clients/`, it takes `_clients/<label>/` first and then only the root files its `files.txt` names, never a file from another version's install (#192).

## What's new in v0.0.4

- Rebuilt from the latest code; the changes for this client are listed here as they land.

## What's new in v0.0.3

- Rebuilt and released together with every other client.

## Running it

Unzip, then run `java -jar ZeldaOnline2.jar` (or double-click it). The
start window offers One-Player mode and Multiplayer mode, with your
nickname and colours.

For multiplayer, start the lobby with `java -jar GServ.jar` on one machine
(port 14801), then type that machine's address in the start window. Every
level is its own room: players meet when they are on the same level.

Arrow keys walk. In multiplayer, Enter opens the chat line.

## Your own files

Put your Zelda Online 2 files in the same folder as the jars:

- run `make_assets.py` on your copy (`python3 make_assets.py SRC assets.zip`)
  and unzip the result next to the jars;
- or unpack the original package next to them.

## What works

- The start window, one-player and multiplayer play on the original levels.
- Walking, collision, level links and signs at the original speed.
- Seeing other players on the same level, with their names, chat and
  colours; the lobby itself.

## Not yet

The real player sprite, the sword, bushes, baddies, chests, the password
save and sound.
