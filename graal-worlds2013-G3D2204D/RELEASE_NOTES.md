# Graal Worlds token G3D2204D: inferred stand-in

A stand-in for the client that sent `G3D2204D`, which gs2lib names
"Graal Worlds", in Delphi (Object Pascal). **No binary that sends this token
is held.** This is the Windows 6.03r7 rebuild sending that token, so a
server can be tested against it. It runs on Linux and Windows.

**Login token: INFERRED, listed only.** `G3D2204D` is gs2lib's `CLVER_WORLDS` and is in the 6.11 connector script's legacy token list. It has not been read from any binary or seen on the wire.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

These zips hold no original Graal code, graphics, sounds or levels. The
program carries small original default graphics and a starter level of its
own, so it runs as it is. Put it in the root of an install you own (or
point it at one with `--data DIR`) and the install's tiles, ganis, heads and
bodies take their place. The shared `graal-assets/` folder next to the
program works too (`graal-assets/Worlds 2013 (inferred)/`, then `graal-assets/common/`).

## What's new in v0.0.5

- [x] **New stand-in.** The Graal Worlds token has a folder, clearly marked inferred: the Windows 6.03r7 rebuild with the token `G3D2204D` and made-up Windows machine fields. Everything else is 6.03r7's.

## Downloads

| Zip | Runs on | Window |
|---|---|---|
| `…-linux.zip` | Linux x86-64 | X11 |
| `…-windows.zip` | Windows, 32-bit | GDI |

Each zip has `Graal2204d` (the client) and the build's README. The test
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
- Login with `G3D2204D`, the platform `win` and made-up machine fields
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
