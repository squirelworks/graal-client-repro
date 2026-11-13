# Graal 6.004 Mac (G3D27090)

The first rebuild of the Mac OS X 6.004 client, in Delphi (Object Pascal).
The original is a Mac OS X program (its x86_64 slice was read) built
from the `quattro_lib` engine. This rebuild runs on Linux and Windows. It is
an early version: most of the game is not there yet.

**Login token: read from the binary, not yet seen on the wire.** `G3D27090` was read from the connect routine of the real Mac 6.004 (x86_64 slice); it has not been run in a lab yet.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

These zips hold no original Graal code, graphics, sounds or levels. The
program carries small original default graphics and a starter level of its
own, so it runs as it is. Put it in the root of an install you own (or
point it at one with `--data DIR`) and the install's tiles, ganis, heads and
bodies take their place. The shared `graal-assets/` folder next to the
program works too (`graal-assets/6.004 Mac/`, then `graal-assets/common/`).

## What's new in v0.0.5

- [x] **New client.** The Mac 6.004 has a folder of its own, started from `graal-6.00beta-20110627-G3D28090` with its own token `G3D27090` (read from the binary). The Mac login line (`mac`, made-up machine hashes, an empty field and a made-up quoted Darwin kernel string), OSTYPE `mac` and code page 0 are inferred from the Mac 5.12 lab run.

## Downloads

| Zip | Runs on | Window |
|---|---|---|
| `…-linux.zip` | Linux x86-64 | X11 |
| `…-windows.zip` | Windows, 32-bit | GDI |

Each zip has `Graal6004mac` (the client) and the build's README. The test
programs are built and run on every release but no longer shipped.

On Windows the first start may show **"Windows protected your PC"**. That
is SmartScreen meeting an unsigned program it has not seen before, not a
virus warning. Either click **More info**, then **Run anyway** (once), or
unblock the zip before you extract it: right-click it, **Properties**,
tick **Unblock**, **OK**. Then nothing in the folder is asked about again.
See [Windows says "Windows protected your PC"](https://github.com/squirelworks/graal-client-repro#windows-says-windows-protected-your-pc).

## What works

- The start screen: nick name, Training, Start. Start fetches the server
  list from `listserver.txt` next to the program, or else
  `listserver.graal.in` on port 14922. Then account, password and Connect.
- Login with `G3D27090`, the platform `mac` and made-up machine fields
  (nothing is read from your machine); the language in its own frame; no
  tamper check.
- The Login server: a server reached by its address alone is called
  Login, and there no characters are drawn until the server's warp (178)
  hands the client on.
- The board, the player and other players drawn from the install's tiles
  and ganis; walking and collision; level links; gmaps.
- A headless mode for stress runs, with JSON stats.

## Not yet

NPCs, baddies, items and weapons; the GS2 script engine and the Login
server's scripted GUI; chat; saved passwords; Options. See the build's
README for the full list.

## Checks behind this release

The test suite (100 checks) runs with range and overflow checks and the
heap tracer, and must end with no unfreed memory. CI also logs two of
these clients into seihai-gserver, has the second see the first, and
walks one through a level link.
