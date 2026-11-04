# Graal 1.41 rev 1 (GNW13110)

A rebuild of the classic Graal 1.41 rev 1 client in Delphi (Object Pascal).
Like the original it is a windowed program: it opens on a start window with
the game mode, the nick name and Start. This is an early, hit-or-miss first
release.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

These zips hold no original Graal code, graphics, sounds or levels. The
program carries small original default graphics and a starter level of its
own, so it runs as it is. Put it at the top of a 1.41 install you own (or
keep a `graal-assets/` folder next to it, or point it at one with
`--data DIR`) and the install's tiles, heads, bodies and levels take their
place.

## Downloads

| Zip | Runs on | Window |
|---|---|---|
| `…-linux.zip` | Linux x86-64 | X11 |
| `…-windows.zip` | Windows, 32-bit | GDI |

Each zip has `Graal141` (the client), its test programs and the build's
README.

## What works

- The 1.41 login: gen-3 cipher, zlib framing, token `GNW13110`, the login
  props with the head as a number, and no language packet.
- The server list from `listserver.graal.in` (port 14923; another can be
  named in `listserver.txt`), with the account and password on the list
  page.
- One Player: the install's `start1.graal`, offline.
- Levels (`.graal`, `.nw`), walking, collision, level links and warps, NPCs,
  items, combat, signs, the map and the level editor.

## Running it

```
Graal141                                                   # start window
GRAAL_PW=... Graal141 --server HOST:PORT --account NAME
Graal141 --level levels/start1.graal                       # offline
```

Arrow keys walk, Esc leaves the game. `Graal141 --help` lists every flag.

## Not yet

This release has only been smoke-tested against the original: start window
and login. Two to four players on one computer, save games, the options
window and drawing from the 1.41 sprite sheet are not done.
