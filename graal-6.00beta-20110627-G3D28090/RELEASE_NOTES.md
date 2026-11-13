# Graal 6.x beta of 2011-06-27 for Linux (G3D28090)

The first rebuild of the Graal 6.x beta of 2011-06-27 for Linux client, in Delphi (Object
Pascal). The original is a Linux program from 2011; this rebuild runs on
Linux and Windows. It is an early version: most of the game (NPCs, items,
weapons, scripts, the scripted login screens) is not there yet.

> **Major defects in fidelity.** The original is one native C++ program (the 6.x `quattro_lib` engine); this release is the Delphi stand-in that speaks its wire protocol. It does not behave like the original in many ways until the 6.x engine track (#109, "Separate own-engine track") reaches this build.

**Login token: tested against the real client.** Read from the binary: both programs build `G3D28090` in their connect routine (static read, 2026-11-13, by the method checked against six tokens already seen on the wire); this rebuild sends the same token.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

These zips hold no original Graal code, graphics, sounds or levels. The
program carries small original default graphics and a starter level of its
own, so it runs as it is. Put it in the root of a 6.x beta (2011-06-27) install you own
(or point it at one with `--data DIR`) and the install's tiles, ganis,
heads and bodies take their place. The shared `graal-assets/` folder next
to the program works too.

## What's new in v0.0.5

- [x] **New client.** 6.x beta (2011-06-27) has a folder of its own, started from `graal-6.01r1-G3D0108A` with its own token `G3D28090`.
- [x] **Machine fields in the original's shape.** The login line now sends `linux`, two fixed made-up MD5 hashes (of SquirrelNIC and SquirrelFS strings), the empty field and a SquirrelOS kernel string (`2.6.38-1-squirrelos  #1-SquirrelOS SMP Mon Jun 27 12:00:00 UTC 2011`), the shape the real client sends. Nothing is read from your machine.

## Downloads

| Zip | Runs on | Window |
|---|---|---|
| `…-linux.zip` | Linux x86-64 | X11 |
| `…-windows.zip` | Windows, 32-bit | GDI |

Each zip has `Graal600b` (the client) and the build's README. The test
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
- Login with `G3D28090`, the platform `linux` and made-up machine
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


The original's own icon: no copy of the original program to take it from
is in the project yet, so the Windows program has the default icon.

## Checks behind this release

The test suite (97 checks) runs with range and overflow checks and the heap
tracer, and must end with no unfreed memory. CI also logs two of these
clients into seihai-gserver, has the second see the first, and walks one
through a level link.
