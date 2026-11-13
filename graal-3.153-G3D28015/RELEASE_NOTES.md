# Graal 3.153 (G3D28015)

The first rebuild of the Graal 3.153 client, in Delphi (Object Pascal).
The original 3.153 is a Mac OS X program built on the Torque engine; this
rebuild runs on Linux and Windows. On the wire 3.153 talks the same
protocol as the Windows 2.31 client. It is an early version: most of the
game (NPCs, items, weapons, the script engine, the 3D mode) is not there
yet.

> **Major defects in fidelity.** This client's Torque layer has not been rebuilt yet (the original is built on the Torque engine), so this release does not behave like the original in many ways. It stays marked this way until the Torque behaviour rebuild (#109, #151, #172) reaches this build.

**Login token: tested against the real client.** The original was run in the lab and `G3D28015` was seen in its login on the wire (Mac OS X lab run in qemu); this rebuild sends the same token.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

These zips hold no original Graal code, graphics, sounds or levels. The
program carries small original default graphics and a starter level of its
own, so it runs as it is. Put it in the root of a 3.153 install you own (or
point it at one with `--data DIR`) and the install's tiles, ganis, heads and
bodies take their place. The shared `graal-assets/` folder next to the
program works too (`graal-assets/3.153/`, then `graal-assets/common/`).

## What's new in v0.0.5

- [x] **The player's actions.** S swings the sword and cuts the bush at its tip, and a second S during the swing spins when the account has the spin attack (STATUS 0x40): 13 ticks of `spin`, then idle. A lifts a bush, sign, pot or stone (as the glove allows), carries it, and A or S throws it; A also opens a chest. D uses the selected weapon: the bomb (`BOMBADD`, 60-tick fuse, a blast that hurts and breaks bushes and pots) or the bow and the fireball shots (`ARROWADD`). Q opens the item list, where the arrow keys pick the weapon. Floor items from the server are drawn, taken by walking over them (`ITEMTAKE`) and time out (`ITEMDEL`); others' bombs, shots, explosions and sword hits hurt with knockback, and death respawns at the level's entry. In `graal304-torque` the install's own key binds reach these through `doA`, `doS`, `doD` and `doQ`. Carried over from the 2.22 rebuild, which 3.x plays as.
- [x] **The Torque program's Options and message boxes.** In `graal304-torque` the Options tabs switch, the Display Driver and Resolution lists fill, and the drop-down lists (Resolution, Display Driver, Language) open and change the setting; a resolution applied in Options resizes the window and is kept for the next start. Message boxes show their text without markup tags. The F2 console shows full lines, the newest at the bottom, with its input line.
- [x] **The server list tries the next list server.** When a list server takes the connection but never answers, or closes it, the client now moves on to the `license/license.graal` hosts after 8 seconds instead of going back to the menu.

## What's new in v0.0.4.2

- [x] **On Windows and macOS too.** The Windows zip holds `graal304-torque.exe` and `Game3153Lib.dll`, and the macOS zips `graal304-torque.app`, so the Torque program runs the 3.153 install there as on Linux.
- [x] **First boot on the Torque engine.** The 3.153 install's own menus now run on the rebuilt Torque engine (`common/torque/guigraal`, `graal304-torque` on Linux), using the PPC script floats, the Mac script folders and 3.153's four extra menu methods. The game library `Game3153Lib` sends 3.153's login.
- [x] **The Torque program ships.** The Linux zip holds `graal304-torque` and `libGame3153Lib.so`: copy both into a 3.153 install and start `graal304-torque` (README, "On the Torque engine"). Nothing from a 3.04 install is needed any more.
- [x] **Its own fonts and logo.** The Mac install ships no font caches; the menu's fonts are now made from the system's Arial (or Liberation Sans, then DejaVu Sans) the way the original makes them, and the `graalscreen3d.jpg` logo draws. The menu runs at 640 × 480 with the edit frames and the language box, and matches the first-run Tiger capture on 98.8 % of its pixels. Known differences: text is a few pixels narrower or wider than the Mac's Arial, and the language box shows `English` where the capture shows it empty.
- [x] **3.04's game fixes carried over.** Own chat goes out as a player prop, the log reaches the host, and walking follows the sheet-type tile rules: the offline tutorial walks, and online levels need 2.22's `arrays.dat` in the install.
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

Each zip has `Graal3153` (the client) and the build's README. The test
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
- The listserver login (`G3D30123newmain` and the account in one frame).
- Login to a server with `G3D28015`, with no tamper check.
- The first props, with `mac` as the system name.
- The board, the player and other players drawn from the install's tiles
  and ganis; walking and collision; level links; gmaps and their edges.
- A headless mode for stress runs, with JSON stats.

## Not yet

NPCs, baddies and server weapons; the item key's lay-down mode; the GS1
script engine; chat; the 3D
mode; the RC file browser and script uploads; server text, class scripts
and gani scripts; precise movement; Options; the UDP channel between
players. See the build's README for the full list.

The original runs on the Torque engine; this release is still the Delphi
stand-in that speaks its wire protocol. The Torque layer is not done.

The original's own icon: no copy of the original program to take it from
is in the project yet, so the Windows program has the default icon.

## Checks behind this release

The test suite (87 checks) runs with range and overflow checks and the heap
tracer, and must end with no unfreed memory. CI also logs two of these
clients into seihai-gserver, has the second see the first, and walks one
through a level link.
