# Graal 3.151 (G3D27015)

The first rebuild of the Graal 3.151 client, in Delphi (Object Pascal) with the rebuilt Torque engine.
The original is the Linux 3.151, a Torque build of the C++ client between 3.04 (Linux) and 3.153 (Mac); its token is one day before 3.153's `G3D28015`, and its install has the same `languages3D` / `levels3d` / `scripts*` layout as the Mac 3.153. It is an early version: most of the game
(NPCs, items, weapons, the script engine, the 3D mode) is not there yet.

> **Major defects in fidelity.** This client's Torque layer has not been rebuilt yet (the original is built on the Torque engine), so this release does not behave like the original in many ways. It stays marked this way until the Torque behaviour rebuild (#303) reaches this build.

**Login token: read from the binary, not yet seen on the wire.** This rebuild sends `G3D27015`, which the token survey read from the original's own connect routine (Graal_analysis `client-internals/version-token-catalogue.md`). No lab run of this build exists yet.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

These zips hold no original Graal code, graphics, sounds or levels. The
program carries small original default graphics and a starter level of its
own, so it runs as it is. Put it in the root of a 3.151 install you own (or
point it at one with `--data DIR`) and the install's tiles, ganis, heads and
bodies take their place.

## What's new in v0.0.5

- [x] **The player's actions.** S swings the sword and cuts the bush at its tip, and a second S during the swing spins when the account has the spin attack (STATUS 0x40): 13 ticks of `spin`, then idle. A lifts a bush, sign, pot or stone (as the glove allows), carries it, and A or S throws it; A also opens a chest. D uses the selected weapon: the bomb (`BOMBADD`, 60-tick fuse, a blast that hurts and breaks bushes and pots) or the bow and the fireball shots (`ARROWADD`). Q opens the item list, where the arrow keys pick the weapon. Floor items from the server are drawn, taken by walking over them (`ITEMTAKE`) and time out (`ITEMDEL`); others' bombs, shots, explosions and sword hits hurt with knockback, and death respawns at the level's entry. In `graal304-torque` the install's own key binds reach these through `doA`, `doS`, `doD` and `doQ`. Carried over from the 2.22 rebuild, which 3.x plays as.
- [x] **Hiding and laying items.** D with a carried bush or stone hides under it (STATUS 0x02, `hiddenstill`/`hidden`, a fifth of the walking speed); D or A comes out, S throws. S held with A, when there is nothing in front to lift or open, picks an item to lay down (S held with A again takes the next one, A lays it two tiles ahead, any other key cancels): rupees, bombs, darts, a heart, or the glove, shield and sword a power down; online a floor item goes out as `ITEMADD`. S held with D picks the next weapon. From Graal_analysis `client-internals/laying-items-and-hiding.md` (3.04 and 2.05 read; no lab capture yet).
- [x] **NPCs, baddies and GS1.** Level NPCs and their GS1 scripts run, through the same script engine and NPC layer as the 2.22 rebuild (`Npc`, `Baddy`, `NpcBridge`): NPCs are drawn and block walking, pushing into one runs its touch script, the sword, bombs and shots fire their events, `replaceani`, signs (read by walking up to them or opening a chest sign), `showstats` and the level's baddies, which hurt, take hits and die. Online, the server's NPC and baddy packets are handled. Not carried over yet: NPC sounds (logged only), the name font, the heights and attached ganis, and file downloads.
- [x] **New client.** A folder for the Linux 3.151 binary, whose token (`G3D27015`) the token survey read from the shipped `graalexe`. It is the 3.153 rebuild with 3.151's token and 3.04's Linux values, and it runs the 3.151 install's own scripts on the rebuilt Torque engine with its own game library (`Game3151Lib`).

## Downloads

| Zip | Runs on | Window |
|---|---|---|
| `…-linux.zip` | Linux x86-64 | X11 |
| `…-windows.zip` | Windows, 32-bit | GDI |
| `…-macos-*.zip` | macOS | Cocoa (the Torque program only) |

Each zip has `Graal3151` (the Pascal client), `graal304-torque` with
`Game3151Lib` (the Torque program and this build's game library) and the
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

The test suite runs with range and overflow checks and the heap tracer, and must end with no unfreed memory. The `torque-guigraal` workflow also runs the Torque program with `Game3151Lib` from the menu to a loopback game server and checks that `G3D27015` arrives in the login.
