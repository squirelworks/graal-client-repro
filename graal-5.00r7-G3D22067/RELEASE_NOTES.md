# Graal 5.00 rev 7 (G3D22067)

The first rebuild of the Graal 5.00 rev 7 client, in Delphi (Object
Pascal). The original is a Windows program from 2007; this rebuild runs on
Linux and Windows. It is an early version: most of the game (NPCs, items,
weapons, scripts, the scripted login screens, the 3D mode) is not there
yet.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

These zips hold no original Graal code, graphics, sounds or levels. The
program carries small original default graphics and a starter level of its
own, so it runs as it is. Put it in the root of a 5.00r7 install you own
(or point it at one with `--data DIR`) and the install's tiles, ganis,
heads and bodies take their place. The shared `graal-assets/` folder next
to the program works too (`graal-assets/5.00r7/`, then
`graal-assets/common/`).

## What's new in v0.0.3

- Faithfulness pass: compared side by side with the original program it was
  rebuilt from, and the differences found brought in line with it.
- Stress tested before release: a long soak with several players walking
  between levels, others connecting and dropping again and again, and a
  level with 80 scripted NPCs, with no crash, error or memory growth.

## Downloads

| Zip | Runs on | Window |
|---|---|---|
| `…-linux.zip` | Linux x86-64 | X11 |
| `…-windows.zip` | Windows, 32-bit | GDI |

Each zip has `Graal500` (the client) and the build's README. The test
programs are built and run on every release but no longer shipped.

On Windows the first start may show **"Windows protected your PC"**. That
is SmartScreen meeting an unsigned program it has not seen before, not a
virus warning. Either click **More info**, then **Run anyway** (once), or
unblock the zip before you extract it: right-click it, **Properties**,
tick **Unblock**, **OK**. Then nothing in the folder is asked about again.
See [Windows says "Windows protected your PC"](https://github.com/squirelworks/graal-delphi#windows-says-windows-protected-your-pc).

## What works

- The start screen: nick name, Training, Start. Start fetches the server
  list from `listserver.txt` next to the program, or else
  `listserver.graal.in` on port 14922. Then account, password and Connect.
- Login with `G3D22067`, the platform `win` and three empty machine
  fields; the language in its own frame; no tamper check.
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

## Checks behind this release

The test suite (94 checks) runs with range and overflow checks and the heap
tracer, and must end with no unfreed memory. CI also logs two of these
clients into seihai-gserver, has the second see the first, and walks one
through a level link.
