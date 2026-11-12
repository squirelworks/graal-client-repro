# Graal 4.04r2 (G3D17026)

The first rebuild of the Graal 4.04r2 client, in Delphi (Object Pascal).
The original 4.04r2 is a Windows program: a Delphi front end over a C++
game engine. This rebuild runs on Linux and Windows. It is an early
version: most of the game (NPCs, items, weapons, the script engine, the
3D mode) is not there yet.

> **Major defects in fidelity.** This client's Torque layer has not been rebuilt yet (its 3D mode runs on Torque), so this release does not behave like the original in many ways. It stays marked this way until the Torque behaviour rebuild (#109, #151, #172) reaches this build.

**Login token: tested against the real client.** The original was run in the lab and `G3D17026` was seen in its login on the wire (lab run); this rebuild sends the same token.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

These zips hold no original Graal code, graphics, sounds or levels. The
program carries small original default graphics and a starter level of its
own, so it runs as it is. Put it in the root of a 4.04r2 install you own (or
point it at one with `--data DIR`) and the install's tiles, ganis, heads and
bodies take their place. The shared `graal-assets/` folder next to the
program works too (`graal-assets/4.04r2/`, then `graal-assets/common/`).

## What's new in v0.0.5

- [x] **Playing from the engine's menus.** With `--engine`, Start now logs in from the engine library: the Login server, the hand-on to the game server, the level in the game screen's playfield, walking with the arrow keys through the menus' own key bindings, and chat from the chat bar.
- [x] **Menu text in Arial.** The engine's menus are drawn in the font and size their scripts name: Windows' own Arial, or Liberation Sans (same widths) on Linux, in place of the launcher's one 16-pixel font. A face with no font file keeps that font.
- [x] **The start menus are drawn.** With `--engine`, the main menu from the install's own engine file now shows in the window, drawn through the launcher with the install's own GUI pictures, and it takes clicks and typing: the nickname box, the account fields, and Offline Test. The animated pictures are not drawn yet.
- [x] **The start menus run.** With `--engine`, the engine library reads the 14 start menus from the install's own `GraalEngine.dll` and runs them on the GS2 script engine, in the order the original makes them, with the account, server-list, offline, options, URL and quit calls they make. They are not drawn yet. The rebuilt library is now `GraalEngineRepro.dll`, so it never replaces the original in an install.
- [x] **The engine library.** As the real 4.04r2, the program can now run as a launcher over an engine library: `GraalEngine.dll` (`libgraalengine.so` on Linux) ships next to it, and `Graal404 --engine` loads it, fills its 94 callback slots, starts it and draws each frame through them. The canvas is empty until the script engine brings the start menus; the normal start screen stays the default.
- [x] **Become a Member.** The original's sign-up page is gone, so with no sign-up page in the licence file (line 3) the button now says none is set instead of opening a dead address.
- [x] **Pictures by kind.** The picture cache keeps each name once per kind (head, body, sword, shield, hat, weapon), because each kind searches its own folders. A picture first asked for without its kind got the built-in stand-in and kept it, so an install's own picture could stay hidden behind the stand-in (in 1.33, `levels/weapons/wbomb1.gif` beside the D button).

## What's new in v0.0.4

- Rebuilt from the latest code; the changes for this client are listed here as they land.
- [x] 4.04r2's own start screen, drawn inside the 640 x 480 game window
  the way the real 4.04r2 does it: the house and title art, the
  Nickname panel, the Play as / Account name / Password panel with the
  Member radio and Save password, Start, and Become a Member, Options and
  Offline Test along the bottom. The pictures are the install's own GUI
  pictures (graalv4screen, graalv4title, the edit box, combo arrow, radio
  and check box), built into the program, at the places measured on the
  real 4.04r2.
- [x] Start logs in to the Login server named in `license/license.graal`,
  as the real 4.04r2 does, instead of asking for a server list. Without
  that file the old start screen and server list are still there.
- [x] Offline Test plays the offline tutorial; Become a Member opens the
  sign-up page the licence file names.
- [x] The game window is titled "G r a a l" with eight spaces spread
  around it at random, as Graal4.exe does.
- [x] Alt+Enter switches to fullscreen and back, as in 4.04r2.

## What's new in v0.0.3

- The Windows program carries its original's own icon (the Graal head, taken from
  the original exe), so Explorer shows it as the original did.
- Stress tested before release: a long soak with several players walking
  between levels, others connecting and dropping again and again, and a
  level with 80 scripted NPCs, with no crash, error or memory growth.

## Downloads

| Zip | Runs on | Window |
|---|---|---|
| `…-linux.zip` | Linux x86-64 | X11 |
| `…-windows.zip` | Windows, 32-bit | GDI |

Each zip has `Graal404` (the client) and the build's README. The test
programs are built and run on every release but no longer shipped.

On Windows the first start may show **"Windows protected your PC"**. That
is SmartScreen meeting an unsigned program it has not seen before, not a
virus warning. Either click **More info**, then **Run anyway** (once), or
unblock the zip before you extract it: right-click it, **Properties**,
tick **Unblock**, **OK**. Then nothing in the folder is asked about again.
See [Windows says "Windows protected your PC"](https://github.com/squirelworks/graal-client-repro#windows-says-windows-protected-your-pc).

## What works

- 4.04r2's own start screen: nickname, account, password, Start, Offline
  Test. Start logs in to the Login server named in the install's
  `license/license.graal`. Without that file, the old start screen asks
  `listserver.graal.in` on port 14922 for a list instead.
- Login with `G3D17026`, the platform `win` and three machine fields,
  which the rebuild leaves empty. No tamper check.
- The Login server: its level is shown with no players on it, and the
  server's hand-over (178) takes the client to the game server.
- The messages after login in the original's order, walking sent as
  precise positions every 50 ms, and the 5-second keep-alive.
- The board, the player and other players drawn from the install's tiles
  and ganis; walking and collision; level links; gmaps and their edges.
- A headless mode for stress runs, with JSON stats.

## Not yet

- [ ] The players walking about on the start screen, and the lamp's glow:
  the real 4.04r2's engine draws live characters there.
- [ ] Options, and Save password: the box ticks but nothing is saved yet.
- [ ] The window cannot be resized by dragging its edge (the real one can);
  Alt+Enter gives fullscreen.
- [ ] The start screen's words are drawn in Liberation Sans, not the
  engine's Arial.
- [ ] NPCs, baddies, items and weapons; the GS1 and GS2 script engines;
  chat; update packages; the 3D mode. See the build's README for the full
  list.

The original runs on the Torque engine; this release is still the Delphi
stand-in that speaks its wire protocol. The Torque layer is not done.

## Checks behind this release

The test suite (105 checks) runs with range and overflow checks and the
heap tracer, and must end with no unfreed memory. CI also logs two of
these clients into seihai-gserver, has the second see the first, and
walks one through a level link.
