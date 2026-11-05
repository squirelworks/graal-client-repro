# Graal 1.28 beta 2 (GSERV013), 0.0.1

A first rebuild of the Graal 1.28 beta 2 client in Delphi (Object Pascal),
for Linux and Windows. It logs in the way 1.28 beta 2 did and plays a level
offline. It is early and many parts still behave like a later Graal: see
"Not yet".

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

The zips hold no original Graal code, game graphics, sounds or levels; the
program carries only the original's start dialog (its form, pictures and icon,
taken from the original program). The
client carries simple graphics of its own.

## What's new in v0.0.3

- The Windows program carries its original's own icon (the sword, taken from
  the original exe), so Explorer shows it as the original did.
- Stress tested before release: a long soak with several players walking
  between levels, others connecting and dropping again and again, and a
  level with 80 scripted NPCs, with no crash, error or memory growth.
- [ ] The start dialog is this build's own. Its form (`TConnectFrame`) is taken
      from the original program and compiled in: the mode list (One Player, One Player Online and Two to Four Players),
      a character list per player, and the online panel, at the same places,
      with the same captions, pictures, fonts, colours and tab order, on the
      original's window classes and frame buttons.
- [ ] The online panel has the original's nick name, server list, port, account,
      password and "Load head/colors from last session" fields. As in the
      original, `graalconfig.txt` keeps the last session's mode, characters, nick
      name, server, account and language, and the dialog opens with them.
- [ ] The character list comes from the install's `headsconfig.txt`, as in the
      original (this build's own 29 characters when there is none). Each entry
      shows its head from its own head file, `heads/headN.gif`.
- [ ] The language list, filled from the install's `language*.txt` files: picking
      Deutsch puts the whole dialog into German, as in the original. In One
      Player the panel shrinks to its nick name row, as in the original.
- [ ] The program's icon is the original's.
- [ ] The game window is shaped as the original's `TAdventure` form.
- [ ] Under Wine, screenshots of the start dialog match the original's pixel for
      pixel (online panel and German captions included).
- [ ] The original's forms, pictures, icons and strings are in `res/`, taken out by
      `scripts/realres/extract_res.py`; the program carries them itself and
      never reads the original program.
- [ ] The game window is a `TAdventure` owned by the hidden application window, with the original's styles and a 640 x 448 client plus the 24-pixel chat field.
- [ ] One Player starts in `house1.graal` at 21.5, 28, the first player's spot from the original's start table (the bed).
- [ ] The status display is drawn from the install's own `state.gif`: the A, S and D buttons with the sword and bomb beside them, the rupee, bomb and arrow counts in the digits of `sprites.gif`, and the hearts, each piece where the original draws it.
- [ ] Alt+Enter switches to 640 x 480 full screen (a topmost pop-up over the whole screen) and back, as the original does.

## Downloads

| Zip | Runs on | Window |
|---|---|---|
| `…-linux.zip` | Linux x86-64 | X11 |
| `…-windows.zip` | Windows, 32-bit | GDI |

Each zip has `Graal128b2` (the client) and the build's README. The test
programs are built and run on every release but no longer shipped.

On Windows the first start may show **"Windows protected your PC"**. That
is SmartScreen meeting an unsigned program it has not seen before, not a
virus warning. Either click **More info**, then **Run anyway** (once), or
unblock the zip before you extract it: right-click it, **Properties**,
tick **Unblock**, **OK**. Then nothing in the folder is asked about again.
See [Windows says "Windows protected your PC"](https://github.com/squirelworks/graal-delphi#windows-says-windows-protected-your-pc).

## Where to put your Graal files

Put `Graal128b2` in a folder and copy the contents of your own 1.28 beta 2 install
next to it: `levels/`, `pics1.png` and the rest, as the install has them.
The program reads only that folder. Without them it uses its own graphics
and starter level.

## What works

- The login line: id 0, `GSERV013`, account and password, sent as one
  zlib frame with no cipher.
- The level the server sends (the board first, then its name), other
  players, walking, links and warps.
- A start screen: Training plays `levels/start1.graal` from your install
  (or the built-in level), and Start offers one server address to connect
  to, as 1.28 beta 2 had no server list. It is `listserver.graal.in:14923`
  until you set `serveraddr=` and `serverport=` in `graalconfig.txt` next
  to the program.

## Not yet

- [ ] The player is drawn with the rebuild's stand-in animations, not the
      build's own sprite sheet and the chosen head; the F1 options window is
      not rebuilt.
- [ ] Linux and macOS keep the shared start screen; the original's dialog is
      Windows only.
- [ ] Two to Four Players start the one-player game; the local multiplayer modes
      are not rebuilt.
- [ ] The character picked in the dialog is not yet drawn in the game.

Most of the game still follows a later Graal: the script commands, the
item list, sound and the editor have not been checked against 1.28 beta 2.
No local 2 to 4 player modes, no UDP, no options page.

## Checks behind this release

The test programs run with range and overflow checks and the heap tracer
and must end with no unfreed memory; they include a fuzz run of the
receive path. CI also logs two of these clients into seihai-gserver on
loopback, has the second see the first, and walks one through a level
link.
