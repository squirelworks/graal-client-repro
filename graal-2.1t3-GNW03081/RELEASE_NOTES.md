# Graal 2.1 test 3 (GNW03081)

A rebuild of the classic Graal 2.1 test 3 client in Delphi (Object Pascal).
Like the original it is a windowed program: it opens on a start window with
Training, the server list from the listserver, and login. This is an early,
hit-or-miss first release.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

These zips hold no original Graal code, graphics, sounds or levels. The
program carries small original default graphics and a starter level of its
own, so it runs as it is. Put it at the top of a Graal install you own (or
keep a `graal-assets/` folder next to it, or point it at one with
`--data DIR`) and the install's tiles, ganis, heads, bodies and levels take
their place.

## Downloads

| Zip | Runs on | Window |
|---|---|---|
| `…-linux.zip` | Linux x86-64 | X11 |
| `…-windows.zip` | Windows, 32-bit | GDI |

Each zip has `Graal21t3` (the client), its test programs and the build's
README.

## What works

- The test 3 login: gen-3 cipher, zlib framing, token `GNW03081`.
- The server list from `listserver.graal.in` (port 14923; another can be
  named in `listserver.txt`), asked for with the account and password.
- Player props up to 45.
- Levels (`.graal`, `.nw`) and big maps, walking, collision, level links
  and warps, NPCs and GS1, items, combat, signs, weapons, baddies, sound,
  the map and the level editor.

## Running it

```
Graal21t3                                                  # start window
GRAAL_PW=... Graal21t3 --server HOST:PORT --account NAME
Graal21t3 --level some.graal                               # offline
```

Arrow keys walk, Esc leaves the game. `Graal21t3 --help` lists every flag.

## Not yet

This release has only been smoke-tested against the original: start window
and login. The test 3 start window layout and its tabbed options window are
not done.
