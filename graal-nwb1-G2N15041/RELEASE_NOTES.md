# Graal NewWorld beta 1 (G2N15041)

A rebuild of the Graal NewWorld beta 1 client in Delphi (Object Pascal). Like the
original it is a windowed program: it opens on a start window with
Training, the server list from the listserver, and login. This is an early,
hit-or-miss first release.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

These zips hold no original Graal code, graphics, sounds or levels. The
program carries small original default graphics and a starter level of its
own, so it runs as it is. Put it at the top of a NewWorld install you own
(or keep a `graal-assets/` folder next to it, or point it at one with
`--data DIR`) and the install's tiles, ganis, heads, bodies and levels take
their place.

## Downloads

| Zip | Runs on | Window |
|---|---|---|
| `…-linux.zip` | Linux x86-64 | X11 |
| `…-windows.zip` | Windows, 32-bit | GDI |

Each zip has `GraalNwb1` (the client), its test programs and the build's
README.

## What works

- The NewWorld login: gen-3 cipher, zlib framing, token `G2N15041`, eight
  colour bytes and the gani by name.
- The `newworld` server list from `listserver.graal.in` (port 14923;
  another can be named in `listserver.txt`).
- The NewWorld tile sheet, tile types, sprites and body from the install.
- Levels (`.graal`, `.nw`) and big maps, walking, collision, level links
  and warps, NPCs and GS1, items, signs, sound, the map and the level
  editor. As in the original there is no built-in sword, bow or baddies.

## Running it

```
GraalNwb1                                                   # start window
GRAAL_PW=... GraalNwb1 --server HOST:PORT --account NAME
GraalNwb1 --level some.nw                                   # offline
```

Arrow keys walk, Esc leaves the game. `GraalNwb1 --help` lists every flag.

## Not yet

This release has only been smoke-tested against the original: start window
and login. The NewWorld HUD and clock, the control NPC, string arrays and
terrain heights are not done.
