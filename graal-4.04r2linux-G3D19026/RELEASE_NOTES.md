# Graal 4.04r2 Linux (G3D19026)

The first rebuild of the Linux 4.04r2 client, in Delphi (Object Pascal).
The original is a Linux x86 program built from the 4.x engine. This rebuild
runs on Linux and Windows. It is an early version: most of the game (NPCs,
items, weapons, the script engine, the 3D mode) is not there yet.

**Login token: tested against the real client.** The real Linux 4.04r2 logged in to a local lab server and sent `G3D19026` in its first frame; this rebuild sends the same token.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

These zips hold no original Graal code, graphics, sounds or levels. The
program carries small original default graphics and a starter level of its
own, so it runs as it is. Put it in the root of an install you own (or
point it at one with `--data DIR`) and the install's tiles, ganis, heads and
bodies take their place. The shared `graal-assets/` folder next to the
program works too (`graal-assets/4.04r2linux/`, then `graal-assets/4.04r2/`, then `graal-assets/4.20r8/`, then `graal-assets/common/`).

## What's new in v0.0.5

- [x] **New client.** The Linux 4.04r2 has a folder of its own, started from `graal-4.11mac-G3D27076` (the 4.x engine on a Unix system) with its own token `G3D19026`, seen on the wire. The platform name `linux`, OSTYPE `linux` and code page 1250 are inferred.

## Downloads

| Zip | Runs on | Window |
|---|---|---|
| `…-linux.zip` | Linux x86-64 | X11 |
| `…-windows.zip` | Windows, 32-bit | GDI |

Each zip has `Graal404r2lx` (the client) and the build's README. The test
programs are built and run on every release but no longer shipped.

On Windows the first start may show **"Windows protected your PC"**. That
is SmartScreen meeting an unsigned program it has not seen before, not a
virus warning. Either click **More info**, then **Run anyway** (once), or
unblock the zip before you extract it: right-click it, **Properties**,
tick **Unblock**, **OK**. Then nothing in the folder is asked about again.
See [Windows says "Windows protected your PC"](https://github.com/squirelworks/graal-client-repro#windows-says-windows-protected-your-pc).

## What works

- The start screen: nick name, Training, Start. Start asks
  `listserver.graal.in` on port 14922 for a list; the Login server named
  in the install's `license/license.graal` is added as an extra row.
  Then account, password and Connect.
- Login with `G3D19026`, the platform `linux` and three machine fields,
  filled with fixed made-up values (nothing is read from your machine).
  No tamper check.
- The Login server: its level is shown with no players on it, and the
  server's hand-over (178) takes the client to the game server.
- The messages after login in the original's order, walking sent as
  precise positions every 50 ms, and the 5-second keep-alive.
- The board, the player and other players drawn from the install's tiles
  and ganis; walking and collision; level links; gmaps and their edges.
- A headless mode for stress runs, with JSON stats.

## Not yet

NPCs, baddies, items and weapons; the GS1 and GS2 script engines; chat;
the server list as the original shows it; update packages; the 3D mode;
saved passwords; Options. See the build's README for the full list.

The original's own icon is not taken yet, so the Windows program has the
default icon.

## Checks behind this release

The test suite (108 checks) runs with range and overflow checks and the
heap tracer, and must end with no unfreed memory. CI also logs two of
these clients into seihai-gserver, has the second see the first, and
walks one through a level link.
