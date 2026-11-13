# Graal 4.20r8 (G3D20126)

The first rebuild of the Graal 4.20r8 client, in Delphi (Object Pascal).
The original 4.20r8 is a Windows program: a Delphi front end over a C++
game engine. This rebuild runs on Linux and Windows. It is an early
version: most of the game (NPCs, items, weapons, the script engine, the
3D mode) is not there yet.

> **Major defects in fidelity.** This client's Torque layer has not been rebuilt yet (its 3D mode runs on Torque), so this release does not behave like the original in many ways. It stays marked this way until the Torque behaviour rebuild (#109, #151, #172) reaches this build.

**Login token: tested against the real client.** The original was run in the lab and `G3D20126` was seen in its login on the wire (lab run); this rebuild sends the same token.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

These zips hold no original Graal code, graphics, sounds or levels. The
program carries small original default graphics and a starter level of its
own, so it runs as it is. Put it in the root of a 4.20r8 install you own (or
point it at one with `--data DIR`) and the install's tiles, ganis, heads and
bodies take their place. The shared `graal-assets/` folder next to the
program works too (`graal-assets/4.20r8/`, then `graal-assets/common/`).

## What's new in v0.0.5

- [x] **Seihai secure login (optional, off by default).** With `--secure-login auto` (or `required`, or `secure_login.txt` in the settings folder), the account and password go sealed to a Seihai game server or list server (`SEI00001`), after the server's key is checked and pinned. Servers that do not know it get the original login under `auto`. Off, the login is byte for byte the original's. This is not in the original 4.20r8.
- [x] **Machine fields in the original's shape.** The login line's three machine fields are no longer empty. They carry fixed made-up MD5 hashes (of SquirrelOS, SquirrelNIC and SquirrelBIOS strings), the shape the real client sends. Nothing is read from your machine.

## What's new in v0.0.4.2

- **The frame cipher steps compressed bodies rounded down** (`len div 4`, at most 4), as the stock 4.04r2 engine and 5.12 do; raw bodies still step `(len + 3) div 4`. seihai-gserver now does the same for this version, and the rebuild had dropped with "bad frame from the server" right after entering a level.
- The C++ host now shares first-frame framing and loopback transport with
  the other existing host. Version-specific wire fields stay in its adapter;
  independent codec and TCP delivery tests do not establish historical login.

- The C++ host honors an explicit --script path: a missing file fails
  before frame construction instead of silently running the bundled demo.

- `Shell420` is the Delphi-shaped shell for the window and the menus.
  It starts `common/torque/host4208`, which reads the four-module engine
  list, registers the engine controls, opens a level-shaped object,
  places a tile, and sends the documented `G3D20126` login line to
  loopback. This engine has no Torque console. Later frames are not built.
- On Windows the engine host calls `WSAStartup` before `getaddrinfo`,
  then sends `G3D20126`. The Linux path is unchanged.
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

Each zip has `Graal420` (the client) and the build's README. The test
programs are built and run on every release but no longer shipped.

On Windows the first start may show **"Windows protected your PC"**. That
is SmartScreen meeting an unsigned program it has not seen before, not a
virus warning. Either click **More info**, then **Run anyway** (once), or
unblock the zip before you extract it: right-click it, **Properties**,
tick **Unblock**, **OK**. Then nothing in the folder is asked about again.
See [Windows says "Windows protected your PC"](https://github.com/squirelworks/graal-client-repro#windows-says-windows-protected-your-pc).

## What works

- The start screen: nick name, Training, Start. Start asks
  `listserver.graal.in` on port 14922 for a list; the Login server named
  in the install's `license/license.graal` is added as an extra row.
  Then account, password and Connect.
- Login with `G3D20126`, the platform `win` and three machine fields,
  which the rebuild leaves empty. No tamper check.
- The Login server: its level is shown with no players on it, and the
  server's hand-over (178) takes the client to the game server.
- The messages after login in the original's order, walking sent as
  precise positions every 50 ms, and the 5-second keep-alive.
- Board changes on the base layer.
- The board, the player and other players drawn from the install's tiles
  and ganis; walking and collision; level links; gmaps and their edges.
- A headless mode for stress runs, with JSON stats.

## Not yet

NPCs, baddies, items and weapons; the GS1 and GS2 script engines; chat;
the server list as the original shows it; update packages; the 3D mode;
saved passwords; Options. See the build's README for the full list.

The original runs on the Torque engine; this release is still the Delphi
stand-in that speaks its wire protocol. The Torque layer is not done.

The original's own icon: no copy of the original program to take it from
is in the project yet, so the Windows program has the default icon.

## Checks behind this release

The test suite (108 checks) runs with range and overflow checks and the
heap tracer, and must end with no unfreed memory. CI also logs two of
these clients into seihai-gserver, has the second see the first, and
walks one through a level link.
