# Graal 1.1.9 Gold Edition (19990211)

A rebuild of the classic Graal 1.1.9 "Gold Edition" client in Delphi
(Object Pascal). Like the original it is a windowed program: it opens on
the game mode, One Player for your own levels or One Player Online with a
connect dialog. This is an early, hit-or-miss first release.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

These zips hold no original Graal code, graphics, sounds or levels. The
program carries small original default graphics and a starter level of its
own, so it runs as it is. Put it at the top of a 1.1.9 install you own (or
keep a `graal-assets/` folder next to it, or point it at one with
`--data DIR`) and the install's tiles and levels take their place.

## Downloads

| Zip | Runs on | Window |
|---|---|---|
| `…-linux.zip` | Linux x86-64 | X11 |
| `…-windows.zip` | Windows, 32-bit | GDI |

Each zip has `Graal119` (the client), its test programs and the build's
README.

## What works

- The 1.1.9 relay link: two links to the game server, the `Graal8` game
  and a room per level, pairing with the players met there, and their
  positions, nicknames, colours, chat lines and board changes.
- The connect dialog, filled with `listserver.graal.in` port 14802
  (another can be named in `listserver.txt`).
- One Player on `levels/level1.graal`: walking, collision and level links
  on the install's tiles.

## Running it

```
Graal119                                    # game mode and connect dialog
Graal119 --level levels/level1.graal        # One Player
Graal119 --server HOST:14802 --nick NAME    # One Player Online
```

Arrow keys walk, Esc leaves the game.

## Not yet

Smoke-tested only. The original's status bar, sprites and letters sheets,
Two and Four Players, save games and web levels are not done yet.
