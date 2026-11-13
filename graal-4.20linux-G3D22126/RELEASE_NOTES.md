# Graal 4.20 Linux (G3D22126)

The first rebuild of the Graal 4.20 Linux client, in Delphi (Object Pascal).
The original is the Linux 4.20 client. Two Linux builds exist, 4.20r6 (2006-12-21) and 4.20r8 (2007-01-15 and 2007-01-17), with different executables and the same token, so one folder covers both. It is an early version: most of the game
(NPCs, items, weapons, the script engine, the 3D mode) is not there yet.

> **Major defects in fidelity.** This client's Torque layer has not been rebuilt yet (its 3D mode runs on Torque), so this release does not behave like the original in many ways. It stays marked this way until the Torque behaviour rebuild (#303) reaches this build.

**Login token: tested against the real client.** Both original Linux 4.20 builds (r6 and r8) were logged in to a local server in the Linux lab VM and sent `G3D22126` (Graal_analysis `protocol/linux-local-login-matrix.md`); this rebuild sends the same token. Only the token was checked; nothing else here is from those runs.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

These zips hold no original Graal code, graphics, sounds or levels. The
program carries small original default graphics and a starter level of its
own, so it runs as it is. Put it in the root of a 4.20 Linux install you own (or
point it at one with `--data DIR`) and the install's tiles, ganis, heads and
bodies take their place.

## What's new in v0.0.5

- [x] **New client.** A folder for 4.20 Linux (`G3D22126`). It is the 4.20r8 rebuild with this build's token and the Linux login values, because no lab run of the real 4.20 Linux exists yet.

## Downloads

| Zip | Runs on | Window |
|---|---|---|
| `…-linux.zip` | Linux x86-64 | X11 |
| `…-windows.zip` | Windows, 32-bit | GDI |

Each zip has `Graal420linux` (the client) and the build's README.

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
