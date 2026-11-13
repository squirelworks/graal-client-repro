# Graal 4.03r1 (G3D11125)

The first rebuild of the Graal 4.03r1 client, in Delphi (Object Pascal).
The original is the Linux 4.03r1, one program built from the 4.x engine (token date stamp 11 December 2005). It is an early version: most of the game
(NPCs, items, weapons, the script engine, the 3D mode) is not there yet.

> **Major defects in fidelity.** This client's Torque layer has not been rebuilt yet (its 3D mode runs on Torque), so this release does not behave like the original in many ways. It stays marked this way until the Torque behaviour rebuild (#303) reaches this build.

**Login token: read from the binary, not yet seen on the wire.** This rebuild sends `G3D11125`, which the token survey read from the original's own connect routine (Graal_analysis `client-internals/version-token-catalogue.md`). No lab run of this build exists yet.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

These zips hold no original Graal code, graphics, sounds or levels. The
program carries small original default graphics and a starter level of its
own, so it runs as it is. Put it in the root of a 4.03r1 install you own (or
point it at one with `--data DIR`) and the install's tiles, ganis, heads and
bodies take their place.

## What's new in v0.0.5

- [x] **New client.** A folder for 4.03r1 Linux (`G3D11125`). It is the 4.20r8 rebuild with this build's token and the Linux login values and 4.04r2's server ids, because no lab run of the real 4.03r1 exists yet.

## Downloads

| Zip | Runs on | Window |
|---|---|---|
| `…-linux.zip` | Linux x86-64 | X11 |
| `…-windows.zip` | Windows, 32-bit | GDI |

Each zip has `Graal403r1` (the client) and the build's README.

On Windows the first start may show **"Windows protected your PC"**. That
is SmartScreen meeting an unsigned program it has not seen before, not a
virus warning. Either click **More info**, then **Run anyway** (once), or
unblock the zip before you extract it: right-click it, **Properties**,
tick **Unblock**, **OK**. Then nothing in the folder is asked about again.
See [Windows says "Windows protected your PC"](https://github.com/squirelworks/graal-client-repro#windows-says-windows-protected-your-pc).

## Not yet

See the build's README, "Not yet, or not known".

## Checks behind this release

The test suite (108 checks) runs with range and overflow checks and the heap tracer, and must end with no unfreed memory.
