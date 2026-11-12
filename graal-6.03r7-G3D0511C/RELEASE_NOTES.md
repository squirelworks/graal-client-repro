# Graal 6.03 rev 7 for Linux (G3D0511C)

The first rebuild of the Graal 6.03 rev 7 Linux client, in Delphi (Object
Pascal). The original is a Linux program from 2012; this rebuild runs on
Linux and Windows. It is an early version: most of the game (NPCs, items,
weapons, scripts, the scripted login screens) is not there yet.

> **Major defects in fidelity.** This client's Torque layer has not been rebuilt yet (the original runs on the Torque engine), so this release does not behave like the original in many ways. It stays marked this way until the Torque behaviour rebuild (#109, #151, #172) reaches this build.

**Login token: tested against the real client.** The original was run in the lab and `G3D0511C` was seen in its login on the wire (Linux lab login); this rebuild sends the same token.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

These zips hold no original Graal code, graphics, sounds or levels. The
program carries small original default graphics and a starter level of its
own, so it runs as it is. Put it in the root of a 6.03r7 install you own
(or point it at one with `--data DIR`) and the install's tiles, ganis,
heads and bodies take their place. The shared `graal-assets/` folder next
to the program works too (`graal-assets/6.03r7/`, then
`graal-assets/common/`).

## What's new in v0.0.5

- Preserves #164's removal of the checklist-only unit and test. The
  Linux token stays `G3D0511C`; no Torque engine is linked.
- Adds a provisional standalone `GRESCR01` header probe. It has no
  client call site, CRC/cache validation or script execution. Want-script
  helpers return diagnostics only, with unknown wire ids.
- Removes startup messages claiming controls were registered and a level
  view opened. Those messages did not implement a Quattro engine.
- [x] **Pictures by kind.** The picture cache keeps each name once per kind (head, body, sword, shield, hat, weapon), because each kind searches its own folders. A picture first asked for without its kind got the built-in stand-in and kept it, so an install's own picture could stay hidden behind the stand-in (in 1.33, `levels/weapons/wbomb1.gif` beside the D button).

## What's new in v0.0.4

- Rebuilt from the latest code; the changes for this client are listed here as they land.

## What's new in v0.0.3

- Stress tested before release: a long soak with several players walking
  between levels, others connecting and dropping again and again, and a
  level with 80 scripted NPCs, with no crash, error or memory growth.

## Downloads

| Zip | Runs on | Window |
|---|---|---|
| `…-linux.zip` | Linux x86-64 | X11 |
| `…-windows.zip` | Windows, 32-bit | GDI |

Each zip has `Graal603` (the client) and the build's README. The test
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
- Login with `G3D0511C`, the platform `linux` and four empty machine
  fields; the language in its own frame; no tamper check.
- The Login server: a server reached by its address alone is called
  Login, and there neither the tiles nor any characters are drawn, until
  the server moves the client on with a server warp. A server picked from
  the list plays at once.
- Server warps: the client logs in again to the named host and port, under
  the new name.
- Long frames (64 KB and more) both ways.
- The first props with `linux` as the system name; movement sent every
  tick in whole pixels.
- The board, the player and other players drawn from the install's tiles
  and ganis; walking and collision; level links; gmaps and their edges.
- A headless mode for stress runs, with JSON stats.

## Not yet

NPCs, baddies, items and weapons; scripts and their cache; the scripted
server list and account screens; chat and its font; layered levels; update
packages. See the build's README for the full list.

The original runs on the Torque engine; this release is still the Delphi
stand-in that speaks its wire protocol. The Torque layer is not done.

The original's own icon: no copy of the original program to take it from
is in the project yet, so the Windows program has the default icon.

## Checks behind this release

The test suite (97 checks) runs with range and overflow checks and the heap
tracer, and must end with no unfreed memory. CI also logs two of these
clients into seihai-gserver, has the second see the first, and walks one
through a level link.
