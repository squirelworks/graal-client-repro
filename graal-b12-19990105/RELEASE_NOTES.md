# 12th Graal (V1.0) (19990105)

The first rebuild of the 12th Graal (V1.0) Graal client from 1998, in Delphi
(Object Pascal). Like the original it has no accounts: it joins a relay
server's game and plays with whoever is on the same level.

**Login token: none.** The original sends no version token, so there is nothing to check here.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

These zips hold no original Graal code, game graphics, sounds or levels.
The program carries the original's start dialog (its form, pictures and
icon, taken from the original program), and it carries small default graphics and a starter level of its own, so
it runs as it is. Put it in a folder with your own copy of this build's
files (or point it at one with `--data DIR`) and its tiles and levels take
their place.

On Windows the first start may show **"Windows protected your PC"**. That
is SmartScreen meeting an unsigned program it has not seen before, not a
virus warning. Either click **More info**, then **Run anyway** (once), or
unblock the zip before you extract it: right-click it, **Properties**,
tick **Unblock**, **OK**. Then nothing in the folder is asked about again.
See [Windows says "Windows protected your PC"](https://github.com/squirelworks/graal-client-repro#windows-says-windows-protected-your-pc).

## What's new in v0.0.4.2

- [x] **F1 Options window.** F1 opens "Options" from the build's own form (TOptions), with the current level's file name filled in. F6 opens it too, as in this build. The other buttons close it and do nothing yet. Linux and macOS draw the form in a window of their own.
- [x] **Its fallback install files.** Every place that sets up the asset search now passes the build's whole version list (`graal-assets/b12/` then `graal-assets/b11/`). Some passed the bare version, so with only `graal-assets/` next to the program those parts found nothing and drew the built-in stand-in art.

- [x] **The player as the original draws it.** The player is drawn from your install's own body sheet and `heads.gif`, posed by the tables of its `arrays.dat`, instead of the project's stand-in art. The default character, Nick, is red with a shield and the head picked in the start dialog.

## What's new in v0.0.4

- Rebuilt from the latest code; the changes for this client are listed here as they land.

## What's new in v0.0.3

- The Windows program carries its original's own icon (the sword, taken from
  the original exe), so Explorer shows it as the original did.
- Stress tested before release: a long soak with several players on one
  relay and others connecting and dropping again and again, with no crash,
  error or memory growth.
- [ ] The start dialog is this build's own. Its form (`TConnectFrame`) is taken
      from the original program and compiled in: One Player and Two Players with a character list each, and the "Online At Cyberjoueur" group with nick name, server and port, at the same
      places, with the same captions, pictures, fonts, colours and tab order.
      Its window has the original's class names, frame buttons and styles, and is
      with no owner window, so it has its own taskbar button, as in the original.
- [ ] The character lists hold this build's 19 characters in its order (Fung Si Yan, Nick, Mandi, ...),
      with the original's defaults. Each entry shows its head from the install's
      `heads.gif`, shrunk the way the original does it (each 2 x 2 block ANDed, which keeps the outlines).
- [ ] The program's icon is the original's.
- [ ] The game window is shaped as the original's `TAdventure` form: titled
      "Graal", 648 x 516 outside, a minimise box and no maximise box, the
      640 x 448 view.
- [ ] Under Wine, screenshots of the start dialog match the original's pixel for
      pixel (open character list included).
- [ ] The original's forms, pictures, icons and strings are in `res/`, taken out by
      `scripts/realres/extract_res.py`; the program carries them itself and
      never reads the original program.
- [ ] The game window is a `TAdventure` owned by the hidden application window, with the original's styles and a 640 x 448 client and no chat field.
- [ ] One Player starts in `house1.graal` at 28.5, 30, the middle of the room, as the original's first frame shows.
- [ ] The status display is drawn from the install's own `state.gif`: the big bomb, the bow, the rupee, bomb and arrow icons, the counts in the digits of `sprites.gif`, and the hearts, each piece at the pixel where the original draws it (the start shows 0 rupees, 10 bombs, 05 arrows and three hearts).
- [ ] Alt+Enter switches to 640 x 480 full screen (a topmost pop-up over the whole screen) and back, as the original does.

## What works

- The original's start dialog on Windows; elsewhere the shared start screen
  (nick name, Training, and Start with the relay server to join).
- Offline play on this build's levels: walking and collision.
- Online play through a relay server: two connections as the original
  opens, the room for the current level, pairing with the other players,
  the state sent to each new partner, and walking seen both ways.

## Not yet

- [ ] Linux and macOS keep the shared start screen; the original's dialog is
      Windows only.
- [ ] Two Players start the one-player game; the local multiplayer modes
      are not rebuilt.
- [ ] Online, the dialog's server field is used only when you change it: the
      host it was filled with is gone, so `listserver.txt` or the rebuild's
      default relay is used.
- [ ] The game itself still differs from the original (see below); it could not
      be compared side by side in the container, where the original stops after
      Start (it needs DirectX).
- [ ] The player is still the stand-in character: the build's own body from
      its sprite sheet and the chosen character's head are not drawn yet.

Chat, items, weapons, enemies, level scripts, signs, saving, sound, and
the build's own character graphics (a stand-in character is drawn). This
is an early version: the comparison with the original, action by action,
comes later.

## Running it

Start `GraalB12` with no arguments for the start screen. From a
terminal: `GraalB12 --level levels/level1.graal --window`, or
`GraalB12 --server HOST:PORT --nick NAME`. `--help` lists every flag.
