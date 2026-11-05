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
| `…-windows.zip` | Windows, 32-bit | GDI |

Each zip has `Graal141` (the client) and the build's README. The test
programs are built and run on every release but no longer shipped.

On Windows the first start may show **"Windows protected your PC"**. That
is SmartScreen meeting an unsigned program it has not seen before, not a
virus warning. Either click **More info**, then **Run anyway** (once), or
unblock the zip before you extract it: right-click it, **Properties**,
tick **Unblock**, **OK**. Then nothing in the folder is asked about again.
See [Windows says "Windows protected your PC"](https://github.com/squirelworks/graal-delphi#windows-says-windows-protected-your-pc).

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
