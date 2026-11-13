# Graal 4.20r6 (G3D21126)

The first rebuild of the Graal 4.20r6 client, in Delphi (Object Pascal).
The original 4.20r6 is a Mac OS X (PowerPC) program built from the 4.x
engine. This rebuild runs on Linux and Windows. It is an early
version: most of the game (NPCs, items, weapons, the script engine, the
3D mode) is not there yet.

> **Major defects in fidelity.** This client's Torque layer has not been rebuilt yet (its 3D mode runs on Torque), so this release does not behave like the original in many ways. It stays marked this way until the Torque behaviour rebuild (#109, #151, #172) reaches this build.

**Login token: listed, not yet tested.** This rebuild sends `G3D21126`, the token listed for the Mac 4.20r6. It has not been seen on the wire or read from the binary yet.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

These zips hold no original Graal code, graphics, sounds or levels. The
program carries small original default graphics and a starter level of its
own, so it runs as it is. Put it in the root of a 4.20r6 install you own (or
point it at one with `--data DIR`) and the install's tiles, ganis, heads and
bodies take their place. The shared `graal-assets/` folder next to the
program works too (`graal-assets/4.20r6/`, then `graal-assets/4.20r8/`,
then `graal-assets/common/`).

## What's new in v0.0.5

- [x] **The real Mac 4.20r6.** This is a new folder for the Mac 4.20r6 binary built 2006-12-21 (from the `Graal4.dmg.bz2` graalonline.com served in March 2007). It sends that build's listed token, `G3D21126`. The client released before as "4.20r6" (`G3D27076`) is the 4.11 Mac and is now `graal-4.11mac-G3D27076`. This rebuild starts as a copy of that one, because no lab run of the real 4.20r6 exists yet.

## Downloads

| Zip | Runs on | Window |
|---|---|---|
| `…-linux.zip` | Linux x86-64 | X11 |
| `…-windows.zip` | Windows, 32-bit | GDI |

Each zip has `Graal420r6` (the client) and the build's README. The test
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
- Login with `G3D21126`, the platform `mac` and three machine fields,
  which the rebuild leaves empty. No tamper check.
- The Login server: its level is shown with no players on it, and the
  server's hand-over (178) takes the client to the game server.
- The messages after login in the original's order, walking sent as
  precise positions every 50 ms, and the 5-second keep-alive.
- Board changes on the base layer.
- The board, the player and other players drawn from the install's tiles
  and ganis; walking and collision; level links; gmaps and their edges.
- A headless mode for stress runs, with JSON stats.

## Not yet

NPCs, baddies, items and weapons; the GS1 and GS2 script engines; chat;
the server list as the original shows it; update packages; the 3D mode;
saved passwords; Options. See the build's README for the full list.

The original runs on the Torque engine; this release is still the Delphi
stand-in that speaks its wire protocol. The Torque layer is not done.

The original's own icon: no copy of the original program to take it from
is in the project yet, so the Windows program has the default icon.

## Checks behind this release

The test suite (108 checks) runs with range and overflow checks and the
heap tracer, and must end with no unfreed memory. CI also logs two of
these clients into seihai-gserver, has the second see the first, and
walks one through a level link.
