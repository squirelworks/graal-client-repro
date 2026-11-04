# Graal 2.0 rev 2 (GNW24011)

A rebuild of the classic Graal 2.0 rev 2 client in Delphi (Object Pascal). Like
the original it is a windowed program: it opens on a start screen with
Training (the offline levels), the server list from the listserver, and
login. This is an early, hit-or-miss first release.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

These zips hold no original Graal code, graphics, sounds or levels. The
program carries small original default graphics and a starter level of its
own, so it runs as it is. Put it at the top of a 2.0 rev 2 install you own (or
keep a `graal-assets/` folder next to it, or point it at one with
`--data DIR`) and the install's tiles, ganis, heads, bodies and levels take
their place.

## Downloads

| Zip | Runs on | Window |
|---|---|---|
| `…-linux.zip` | Linux x86-64 | X11 |
| `…-windows.zip` | Windows, 32-bit (as 2.0 rev 2 itself was) | GDI |

Each zip has `Graal200r2` (the client), its test programs and the build's
README.

## What works

- The 2.0 rev 2 login: gen-3 cipher, zlib framing, token `GNW24011`.
- The server list from `listserver.graal.in` (port 14923; another can be
  named in `listserver.txt`), then account and password.
- Levels (`.graal`, `.zelda`) and the big map, drawn from the install's
  tiles and ganis; walking, collision, level links and warps.
- NPCs and the GS1 script engine, items, combat, signs, weapons, baddies,
  sound, the map and the level editor.
- A headless mode for stress runs.

## Running it

```
Graal200r2                                                   # start screen
GRAAL_PW=... Graal200r2 --server HOST:PORT --account NAME
Graal200r2 --level some.graal                                # offline
```

Arrow keys walk, Esc leaves the game. `Graal200r2 --help` lists every flag.

## Not yet

This release has only been smoke-tested against the original: start screen
and login. Chat bubbles, the Options page, UDP peer traffic and parts of
GS1 are not done.
