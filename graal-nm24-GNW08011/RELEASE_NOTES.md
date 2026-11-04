# Graal NewMain 24 (GNW08011)

A rebuild of the Graal NewMain 24 client in Delphi (Object Pascal). Like the
original it is a windowed program: it opens on a start window with
Training, the server list from the listserver, and login. This is an early,
hit-or-miss first release.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

These zips hold no original Graal code, graphics, sounds or levels. The
program carries small original default graphics and a starter level of its
own, so it runs as it is. Put it at the top of a NewMain install you own
(or keep a `graal-assets/` folder next to it, or point it at one with
`--data DIR`) and the install's tiles, ganis, heads, bodies and levels take
their place.

## Downloads

| Zip | Runs on | Window |
|---|---|---|
| `…-linux.zip` | Linux x86-64 | X11 |
| `…-windows.zip` | Windows, 32-bit | GDI |

Each zip has `GraalNm24` (the client), its test programs and the build's
README.

## What works

- The NewMain login: gen-3 cipher, zlib framing, token `GNW08011`, no
  LANGUAGE packet, player props up to 36.
- The `newmain` server list from `listserver.graal.in` (port 14923;
  another can be named in `listserver.txt`).
- Levels (`.graal`, `.nw`) and big maps, walking, collision, level links
  and warps, NPCs and GS1, items, signs, the sword, bow, bombs and baddies,
  sound, the map and the level editor.

## Running it

```
GraalNm24                                                   # start window
GRAAL_PW=... GraalNm24 --server HOST:PORT --account NAME
GraalNm24 --level some.nw                                   # offline
```

Arrow keys walk, Esc leaves the game. `GraalNm24 --help` lists every flag.

## Not yet

This release has only been smoke-tested against the original: start window
and login. The file requests at login, NewMain's first gani system and the
1.42 level features are not done.
