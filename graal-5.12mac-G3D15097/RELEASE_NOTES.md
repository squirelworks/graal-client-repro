# Graal 5.12 Mac (G3D15097)

The first rebuild of the Mac OS X 5.12 client, in Delphi (Object Pascal).
The original is a Mac OS X (PowerPC) program built from the same engine
source as the Windows 5.12. This rebuild runs on Linux and Windows. It is an
early version: most of the game is not there yet.

**Login token: tested against the real client.** The real Mac 5.12 ran unchanged on Mac OS X 10.4 in the lab (qemu, PowerPC) and sent `G3D15097` in its login; this rebuild sends the same token.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

These zips hold no original Graal code, graphics, sounds or levels. The
program carries small original default graphics and a starter level of its
own, so it runs as it is. Put it in the root of an install you own (or
point it at one with `--data DIR`) and the install's tiles, ganis, heads and
bodies take their place. The shared `graal-assets/` folder next to the
program works too (`graal-assets/5.12 Mac/`, then `graal-assets/common/`).

## What's new in v0.0.5

- [x] **New client.** The Mac 5.12 has a folder of its own, started from `graal-5.12-G3D14097` with its own token `G3D15097` (seen on the wire in the Mac lab run of 2026-11-13), the Mac login line (`mac`, made-up machine hashes and a made-up quoted Darwin kernel string), OSTYPE `mac` and code page 0, and no compression of every frame, as that run saw.

## Downloads

| Zip | Runs on | Window |
|---|---|---|
| `…-linux.zip` | Linux x86-64 | X11 |
| `…-windows.zip` | Windows, 32-bit | GDI |

Each zip has `Graal512mac` (the client) and the build's README. The test
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
- Login with `G3D15097`, the platform `mac` and made-up machine fields
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

The Windows 5.12 launcher's Players window and tray icon are carried over;
the Mac program may have neither.

## Checks behind this release

The test suite (99 checks) runs with range and overflow checks and the
heap tracer, and must end with no unfreed memory. CI also logs two of
these clients into seihai-gserver, has the second see the first, and
walks one through a level link.
