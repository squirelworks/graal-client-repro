# Graal 6.0.3.4 for Windows (G3D2505C)

The first rebuild of the Graal 6.0.3.4 for Windows client, in Delphi (Object
Pascal). The original is a Windows program from 2012; this rebuild runs on
Linux and Windows. It is an early version: most of the game (NPCs, items,
weapons, scripts, the scripted login screens) is not there yet.

> **Major defects in fidelity.** The original is one native C++ program (the 6.x `quattro_lib` engine); this release is the Delphi stand-in that speaks its wire protocol. It does not behave like the original in many ways until the 6.x engine track (#109, "Separate own-engine track") reaches this build.

**Login token: read from the original.** Read from memory: the real 6.0.3.4 was run in a Windows 10 lab VM (2026-11-13) and `G3D2505C` was read from a dump of the running client, next to its "Connecting to the game server" text; it matches the public version list; this rebuild sends the same token.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

These zips hold no original Graal code, graphics, sounds or levels. The
program carries small original default graphics and a starter level of its
own, so it runs as it is. Put it in the root of a 6.0.3.4 install you own
(or point it at one with `--data DIR`) and the install's tiles, ganis,
heads and bodies take their place. The shared `graal-assets/` folder next
to the program works too.

## What's new in v0.0.5

- [x] **Seihai secure login (optional, off by default).** With `--secure-login auto` (or `required`, or `secure_login.txt` in the settings folder), the account and password go sealed to a Seihai game server or list server (`SEI00001`), after the server's key is checked and pinned. Servers that do not know it get the original login under `auto`. Off, the login is byte for byte the original's. This is not in the original 6.0.3.4.
- [x] **New client.** 6.0.3.4 has a folder of its own, started from `graal-6.03r7-G3D0511C` with its own token `G3D2505C` and the Windows login tail (`win` and four machine fields) and `win` as its system name.

## Downloads

| Zip | Runs on | Window |
|---|---|---|
| `…-linux.zip` | Linux x86-64 | X11 |
| `…-windows.zip` | Windows, 32-bit | GDI |

Each zip has `Graal6034` (the client) and the build's README. The test
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
- Login with `G3D2505C`, the platform `win` and four empty machine
  fields; the language in its own frame; no tamper check.
- The Login server: a server reached by its address alone is called
  Login, and there neither the tiles nor any characters are drawn, until
  the server moves the client on with a server warp. A server picked from
  the list plays at once.
- Server warps: the client logs in again to the named host and port, under
  the new name.
- Long frames (64 KB and more) both ways.
- The first props with `win` as the system name; movement sent every
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
