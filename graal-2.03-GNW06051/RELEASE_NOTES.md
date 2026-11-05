# Graal 2.03 (GNW06051)

A rebuild of the classic Graal 2.03 client in Delphi (Object Pascal). Like
the original it is a windowed program: it opens on a start screen with
Training (the offline levels), the server list from the listserver, and
login. This is an early, hit-or-miss first release.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

These zips hold no original Graal code, graphics, sounds or levels. The
program carries small original default graphics and a starter level of its
own, so it runs as it is. Put it at the top of a 2.03 install you own (or
keep a `graal-assets/` folder next to it, or point it at one with
`--data DIR`) and the install's tiles, ganis, heads, bodies and levels take
their place.

## What's new in v0.0.3

- Faithfulness pass: compared side by side with the original program it was
  rebuilt from, and the differences found brought in line with it.
- Stress tested before release: a long soak with several players walking
  between levels, others connecting and dropping again and again, and a
  level with 80 scripted NPCs, with no crash, error or memory growth.

## Downloads

| Zip | Runs on | Window |
|---|---|---|
| `…-linux.zip` | Linux x86-64 | X11 |
| `…-windows.zip` | Windows, 32-bit (as 2.03 itself was) | GDI |

Each zip has `Graal203` (the client) and the build's README. The test
programs are built and run on every release but no longer shipped.

On Windows the first start may show **"Windows protected your PC"**. That
is SmartScreen meeting an unsigned program it has not seen before, not a
virus warning. Either click **More info**, then **Run anyway** (once), or
unblock the zip before you extract it: right-click it, **Properties**,
tick **Unblock**, **OK**. Then nothing in the folder is asked about again.
See [Windows says "Windows protected your PC"](https://github.com/squirelworks/graal-delphi#windows-says-windows-protected-your-pc).

## What works

- The 2.03 login: gen-3 cipher, zlib framing, token `GNW06051`.
- The server list from `listserver.graal.in` (port 14923; another can be
  named in `listserver.txt`), then account and password.
- Levels (`.graal`, `.zelda`) and the big map, drawn from the install's
  tiles and ganis; walking, collision, level links and warps.
- NPCs and the GS1 script engine, items, combat, signs, weapons, baddies,
  sound, the map and the level editor.
- A headless mode for stress runs.

## Running it

```
Graal203                                                   # start screen
GRAAL_PW=... Graal203 --server HOST:PORT --account NAME
Graal203 --level some.graal                                # offline
```

Arrow keys walk, Esc leaves the game. `Graal203 --help` lists every flag.

## Not yet

This release has only been smoke-tested against the original: start screen
and login. Chat bubbles, the Options page, UDP peer traffic and parts of
GS1 are not done.
