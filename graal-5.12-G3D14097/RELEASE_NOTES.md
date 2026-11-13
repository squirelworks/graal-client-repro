# Graal 5.12 (G3D14097)

The first rebuild of the Graal 5.12 client, in Delphi (Object Pascal)
over the rebuilt C++ engine library. The original is a Windows program
from October 2007; this rebuild runs on
Linux and Windows. It is an early version: most of the game (NPCs, items,
weapons, scripts, the scripted login screens, the 3D mode) is not there
yet.

> **Major defects in fidelity.** This client's Torque layer has not been rebuilt yet (its 3D mode runs on Torque), so this release does not behave like the original in many ways. It stays marked this way until the Torque behaviour rebuild (#109, #151, #172) reaches this build.

**Login token: tested against the real client.** The original was run in the lab and `G3D14097` was seen in its login on the wire (lab run); this rebuild sends the same token.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

These zips hold no original Graal code, graphics, sounds or levels. The
program carries small original default graphics and a starter level of its
own, so it runs as it is. Put it in the root of a 5.12 install you own
(or point it at one with `--data DIR`) and the install's tiles, ganis,
heads and bodies take their place. The shared `graal-assets/` folder next
to the program works too (`graal-assets/5.12/`, then
`graal-assets/common/`).

## What's new in v0.0.5

- [x] **New client.** 5.12 has a folder of its own, started from 5.00r7 with 5.12's wire rules: the token `G3D14097`, the quoted Windows version as a fifth login field, every short body zlib-compressed, and 5.12's cipher step for compressed frames.
- [x] **The engine launcher.** `Graal512 --engine` runs over the rebuilt engine library as the 5.0 launcher: the install's own 5.12 start menus, and Start logs in through the engine's session (the Login server, the hand-on, the level, walking with the arrows and the chat bar).
- [x] **3D servers start their 3D link.** Picking a server whose name starts with `3 ` loads the rebuilt 3D library (`libgraal3dengine.so` / `Graal3DEngineRepro.dll`) beside the engine, connects again, and runs the Torque link on port + 1 each frame, as the original launcher does: handshake, mission start and login step 6 against a protocol-24 server. Nothing of the 3D world is drawn yet.
- [x] **Art and walls in the engine launcher.** The engine's session reads the tile sheet (also from `levels/tiles/`), heads, bodies and `arrays.dat` from `graal-assets/5.12/` and `graal-assets/common/` next to the program as well as from the install, and asks the server (23) for a tile sheet or player image it lacks, keeping what comes in `levels/images/downloads/`, as a 5.12 install does.
- [x] **The launcher's window.** With `--engine` the game window is 5.12's 800 x 600, titled with the server's name spaced out once logged in ("L a b   S e r v e r"), and the program carries the original 5.12 icon.

## Downloads

| Zip | Runs on | Window |
|---|---|---|
| `…-linux.zip` | Linux x86-64 | X11 |
| `…-windows.zip` | Windows, 32-bit | GDI |

Each zip has `Graal512`, the engine library (the client) and the build's README. The test
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
- Login with `G3D14097`, the platform `win`, three empty machine fields
  and the quoted Windows version; the language in its own frame; no tamper
  check. Every frame zlib-compressed, with 5.12's cipher step.
- The Login server: a server reached by its address alone is called
  Login, and there the level is drawn but no characters, until the server
  moves the client on with a server warp. A server picked from the list
  plays at once.
- Server warps: the client logs in again to the named host and port, under
  the new name.
- The first props with `win` as the system name; movement sent every tick
  in whole pixels.
- The board, the player and other players drawn from the install's tiles
  and ganis; walking and collision; level links; gmaps and their edges.
- A headless mode for stress runs, with JSON stats.

## Not yet

NPCs, baddies, items and weapons; scripts (class, weapon and gani scripts
and their cache); the scripted server list and account screens; chat;
layered levels; update packages; the 3D mode. See the build's README for
the full list.

The original runs on the Torque engine; this release is still the Delphi
stand-in that speaks its wire protocol. The Torque layer is not done.


## Checks behind this release

The test suite (99 checks, and the engine launcher's own) runs with range and overflow checks and the heap
tracer, and must end with no unfreed memory. CI also logs two of these
clients into seihai-gserver, has the second see the first, and walks one
through a level link.
