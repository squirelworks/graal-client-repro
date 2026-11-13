# Graal 3.01 (G3D27063)

The first rebuild of the Graal 3.01 client, in Delphi (Object Pascal) with the rebuilt Torque engine.
The original is the Linux 3.01, a Torque build of the C++ client (the token's date stamp, 27 June 2003, is one day before the 2.2 Windows token `GNW28063`). It is an early version: most of the game
(NPCs, items, weapons, the script engine, the 3D mode) is not there yet.

> **Major defects in fidelity.** This client's Torque layer has not been rebuilt yet (the original is built on the Torque engine), so this release does not behave like the original in many ways. It stays marked this way until the Torque behaviour rebuild (#303) reaches this build.

**Login token: read from the binary, not yet seen on the wire.** This rebuild sends `G3D27063`, which the token survey read from the original's own connect routine (Graal_analysis `client-internals/version-token-catalogue.md`). No lab run of this build exists yet.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

These zips hold no original Graal code, graphics, sounds or levels. The
program carries small original default graphics and a starter level of its
own, so it runs as it is. Put it in the root of a 3.01 install you own (or
point it at one with `--data DIR`) and the install's tiles, ganis, heads and
bodies take their place.

## What's new in v0.0.5

- [x] **The player's actions.** S swings the sword and cuts the bush at its tip, and a second S during the swing spins when the account has the spin attack (STATUS 0x40): 13 ticks of `spin`, then idle. A lifts a bush, sign, pot or stone (as the glove allows), carries it, and A or S throws it; A also opens a chest. D uses the selected weapon: the bomb (`BOMBADD`, 60-tick fuse, a blast that hurts and breaks bushes and pots) or the bow and the fireball shots (`ARROWADD`). Q opens the item list, where the arrow keys pick the weapon. Floor items from the server are drawn, taken by walking over them (`ITEMTAKE`) and time out (`ITEMDEL`); others' bombs, shots, explosions and sword hits hurt with knockback, and death respawns at the level's entry. In `graal304-torque` the install's own key binds reach these through `doA`, `doS`, `doD` and `doQ`. Carried over from the 2.22 rebuild, which 3.x plays as.
- [x] **New client.** A folder for the Linux 3.01 binary, whose token (`G3D27063`) the token survey read from the shipped `graalexe`. It is the 3.04 rebuild with 3.01's token and the gen-4 game link of a client type 4, and it runs on the rebuilt Torque engine with its own game library (`Game301Lib`).

## Downloads

| Zip | Runs on | Window |
|---|---|---|
| `…-linux.zip` | Linux x86-64 | X11 |
| `…-windows.zip` | Windows, 32-bit | GDI |
| `…-macos-*.zip` | macOS | Cocoa (the Torque program only) |

Each zip has `Graal301` (the Pascal client), `graal304-torque` with
`Game301Lib` (the Torque program and this build's game library) and the
build's README.

On Windows the first start may show **"Windows protected your PC"**. That
is SmartScreen meeting an unsigned program it has not seen before, not a
virus warning. Either click **More info**, then **Run anyway** (once), or
unblock the zip before you extract it: right-click it, **Properties**,
tick **Unblock**, **OK**. Then nothing in the folder is asked about again.
See [Windows says "Windows protected your PC"](https://github.com/squirelworks/graal-client-repro#windows-says-windows-protected-your-pc).

## Not yet

See the build's README, "Not yet, or not known".

## Checks behind this release

The test suite runs with range and overflow checks and the heap tracer, and must end with no unfreed memory. The `torque-guigraal` workflow also runs the Torque program with `Game301Lib` from the menu to a loopback game server and checks that `G3D27063` arrives in the login.
