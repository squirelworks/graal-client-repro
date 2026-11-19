# Graal 3.0beta (G3D16053)

The first rebuild of the Graal 3.0beta client, in Delphi (Object Pascal) with the rebuilt Torque engine.
The original is the Linux 3.0 beta, the first Torque build of the C++ client (spring 2003; the token's date stamp, 16 May 2003, is one day after the 2.19 Windows token `GNW15053`). It is an early version: most of the game
(NPCs, items, weapons, the script engine, the 3D mode) is not there yet.

> **Major defects in fidelity.** This client's Torque layer has not been rebuilt yet (the original is built on the Torque engine), so this release does not behave like the original in many ways. It stays marked this way until the Torque behaviour rebuild (#303) reaches this build.

**Login token: read from the binary, not yet seen on the wire.** This rebuild sends `G3D16053`, which the token survey read from the original's own connect routine (Graal_analysis `client-internals/version-token-catalogue.md`). No lab run of this build exists yet.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

These zips hold no original Graal code, graphics, sounds or levels. The
program carries small original default graphics and a starter level of its
own, so it runs as it is. Put it in the root of a 3.0beta install you own (or
point it at one with `--data DIR`) and the install's tiles, ganis, heads and
bodies take their place.

## What's new in v0.0.5

- [x] **Server weapons, NPC sounds and file downloads.** A weapon the server adds (`NPCWEAPONADD`: name, image, GS1 script) joins the item list and keeps its script; D runs its `weaponfired` with the weapon at the player's centre, it gets `playerenters` on the next tick and on each new level, its timeouts run on this client, `callweapon` reaches it, `isweapon` is true inside it, and `NPCWEAPONDEL` removes it (Graal_analysis `client-internals/feature-specs/02-weapons-combat.md`, `npc-library/gs1-event-parameters-205r2.md`). NPC `play`, `playlooped` and `stopsound`, and baddy sounds, play the install's `sounds/*.wav` at the NPC (`torque/304-audio-ui.md`); looped ones stop on a new level. The sound is on in `graal304-torque` (`--nosound` turns it off) and off in tests and stress runs. A picture or gani the install lacks is asked for with `WANTFILE` once the session is up; a `FILE` the server sends is kept for the session and drawn, large files come in pieces (`LARGEFILESTART`, `LARGEFILESIZE`, `LARGEFILEEND`), and the log has 3.04's `File download:` lines (`torque/304-net.md`). Weapon scripts that use commands the NPC layer lacks still log them.
- [x] **Torque is the default entrypoint.** With no arguments, `Graal30b` starts `graal304-torque` beside it with this build's `Game30bLib` (install menus, server list, login with G3D16053). Pascal is the fallback: `--pascal`, or `GRAAL_PASCAL=1` / `GRAAL_PASCAL_GAME=1`, or when torque is missing / no `DISPLAY`. CLI and stress stay in Pascal. CI runs the Torque FakeServer loopback for the Game30bLib library.
- [x] **The player's actions.** S swings the sword and cuts the bush at its tip, and a second S during the swing spins when the account has the spin attack (STATUS 0x40): 13 ticks of `spin`, then idle. A lifts a bush, sign, pot or stone (as the glove allows), carries it, and A or S throws it; A also opens a chest. D uses the selected weapon: the bomb (`BOMBADD`, 60-tick fuse, a blast that hurts and breaks bushes and pots) or the bow and the fireball shots (`ARROWADD`). Q opens the item list, where the arrow keys pick the weapon. Floor items from the server are drawn, taken by walking over them (`ITEMTAKE`) and time out (`ITEMDEL`); others' bombs, shots, explosions and sword hits hurt with knockback, and death respawns at the level's entry. In `graal304-torque` the install's own key binds reach these through `doA`, `doS`, `doD` and `doQ`. Carried over from the 2.22 rebuild, which 3.x plays as.
- [x] **Hiding and laying items.** D with a carried bush or stone hides under it (STATUS 0x02, `hiddenstill`/`hidden`, a fifth of the walking speed); D or A comes out, S throws. S held with A, when there is nothing in front to lift or open, picks an item to lay down (S held with A again takes the next one, A lays it two tiles ahead, any other key cancels): rupees, bombs, darts, a heart, or the glove, shield and sword a power down; online a floor item goes out as `ITEMADD`. S held with D picks the next weapon. From Graal_analysis `client-internals/laying-items-and-hiding.md` (3.04 and 2.05 read; no lab capture yet).
- [x] **NPCs, baddies and GS1.** Level NPCs and their GS1 scripts run, through the same script engine and NPC layer as the 2.22 rebuild (`Npc`, `Baddy`, `NpcBridge`): NPCs are drawn and block walking, pushing into one runs its touch script, the sword, bombs and shots fire their events, `replaceani`, signs (read by walking up to them or opening a chest sign), `showstats` and the level's baddies, which hurt, take hits and die. Online, the server's NPC and baddy packets are handled. Not carried over yet: the name font, the heights and attached ganis.
- [x] **New client.** A folder for the Linux 3.0beta binary, whose token (`G3D16053`) the token survey read from the shipped `graalexe`. It is the 3.04 rebuild with 3.0beta's token and the gen-4 game link of a client type 4, and it runs on the rebuilt Torque engine with its own game library (`Game30bLib`).

## Downloads

| Zip | Runs on | Window |
|---|---|---|
| `…-linux.zip` | Linux x86-64 | X11 |
| `…-windows.zip` | Windows, 32-bit | GDI |
| `…-macos-*.zip` | macOS | Cocoa (the Torque program only) |

Each zip has `Graal30b` (the Pascal client), `graal304-torque` with
`Game30bLib` (the Torque program and this build's game library) and the
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

The test suite runs with range and overflow checks and the heap tracer, and must end with no unfreed memory. The `torque-guigraal` workflow also runs the Torque program with `Game30bLib` from the menu to a loopback game server and checks that `G3D16053` arrives in the login.
