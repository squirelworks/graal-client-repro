# Graal 3.04 for Linux (G3D03014)

The first rebuild of the Graal 3.04 Linux client, in Delphi (Object
Pascal). The original 3.04 is a C++ program on the Torque engine; on the
wire it talks the same protocol as the Windows 2.22 client, so this rebuild
starts from the 2.22 one and changes what 3.04 does differently. It is an
early version: most of the game (NPCs, items, weapons, the script engine)
is not there yet.

> **Major defects in fidelity.** This client's Torque layer has not been rebuilt yet (the original is built on the Torque engine), so this release does not behave like the original in many ways. It stays marked this way until the Torque behaviour rebuild (#109, #151, #172) reaches this build.

**Login token: tested against the real client.** The original was run in the lab and `G3D03014` was seen in its login on the wire (Linux lab run); this rebuild sends the same token.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

These zips hold no original Graal code, graphics, sounds or levels. The
program carries small original default graphics and a starter level of its
own, so it runs as it is. Put it in the root of a 3.04 install you own (or
point it at one with `--data DIR`) and the install's tiles, ganis, heads and
bodies take their place. The shared `graal-assets/` folder next to the
program works too (`graal-assets/3.04/`, then `graal-assets/common/`).

## What's new in v0.0.5

- [x] **The game as a Torque control.** The 2D game now also builds as a library (`src/Game304Lib.lpr`) that the Torque console engine hosts as `GuiGraalCtrl` (`common/torque/guigraal`): the install's own main menu, server list and key scripts reach it through the control's 31 methods. Not in the release zip yet; `tq-play` runs it.
- [x] **The Torque program ships (Linux).** The Linux zip now holds `graal304-torque` and the game library `libGame304Lib.so`. Copied into a 3.04 install, it runs the install's own Torque menus and the game in a window. Started outside an install, it says where to put it.
- [x] **Torque menu in a window.** `graal304-torque` (`common/torque/guigraal`) opens the install's own Torque main menu in an X11 window: clicks reach buttons, text edits and the server list, keys go through `moveMap`, F2 opens the console, and the game draws inside the `Adventure` control. A text edit filled by `setText` now reads back through `getValue`, so the account typed on the menu reaches the listserver. Not in the release zip yet.
- [x] **Tiles from a 3.04 install.** An install root with its own `common/` folder was taken for a `graal-assets` folder, so `levels/tiles/picso.png` and the tile definitions were not found; the tutorial levels now draw with their own sheet.
- [x] **800 x 600 window.** The game opens at 800 x 600, as the real 3.04 does, not 640 x 480; the view shows more of the level, it is not scaled up.
- The C++ host now shares first-frame framing and loopback transport with
  the other existing host. Version-specific wire fields stay in its adapter;
  independent codec and TCP delivery tests do not establish historical login.

- The C++ host honors an explicit --script path: a missing file fails
  before frame construction instead of silently running the bundled demo.

- GuiGraalCtrl's method names, the draw types, and the nine module names
  stay in `TorqueNames304` as a name table. That unit is not the booting
  host, and this folder does not link the Pascal units under
  `common/torque`. The TGE 1.2 module list stays where it was.
- `common/torque/host304` reads the nine-module list, registers the
  3.04 controls, runs one TorqueScript that opens the level view and
  moves a camera, logs each GuiGraalCtrl stub, and sends this folder's
  login-shaped first frame (`G3D03014`) to the loopback address.
  `scripts/build.sh` builds it. The script is not the install's
  `main.cs`. Later frames are not built.
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

Each zip has `Graal304` (the client) and the build's README. The test
programs are built and run on every release but no longer shipped.

On Windows the first start may show **"Windows protected your PC"**. That
is SmartScreen meeting an unsigned program it has not seen before, not a
virus warning. Either click **More info**, then **Run anyway** (once), or
unblock the zip before you extract it: right-click it, **Properties**,
tick **Unblock**, **OK**. Then nothing in the folder is asked about again.
See [Windows says "Windows protected your PC"](https://github.com/squirelworks/graal-client-repro#windows-says-windows-protected-your-pc).

## What works

- The start screen: nick name, Training, Start. Start fetches the server
  list from `listserver.graal.in` on port 14922 (or the host in
  `listserver.txt` next to the program); the hosts in the install's
  `license/license.graal` are tried after it. Then account, password and Connect.
- The 3.04 listserver login: id 7 (`G3D30123newmain`) and the account in
  one frame, the list back in gen 5.
- Login to a server as 3.04 does it: `G3D03014`, then the language and the
  two map files in the same first frame, and no tamper check, ever.
- The first props as 3.04 sends them (`linux`, code page 1250), and no
  periodic message over TCP.
- The board, the player and other players drawn from the install's tiles
  and ganis; walking and collision; level links; gmaps and their edges.
- A headless mode for stress runs, with JSON stats.

## Not yet

NPCs, baddies, items and weapons; the GS1 script engine; chat; Options;
the UDP channel between players; the profile and PM windows; the
`GSERVL01` level format; checking the licence file's signature. See the
build's README for the full list.

The original runs on the Torque engine; this release is still the Delphi
stand-in that speaks its wire protocol. The Torque layer is not done.

The original's own icon: no copy of the original program to take it from
is in the project yet, so the Windows program has the default icon.

## Checks behind this release

The test suite (87 checks) runs with range and overflow checks and the heap
tracer, and must end with no unfreed memory. CI also logs two of these
clients into seihai-gserver, has the second see the first, and walks one
through a level link.
