# 5th Graal (19981019)

The first rebuild of the 5th Graal Graal client from 1998, in Delphi
(Object Pascal). Like the original it has no accounts: it joins a relay
server's game and plays with whoever is on the same level.

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
See [Windows says "Windows protected your PC"](https://github.com/squirelworks/graal-delphi#windows-says-windows-protected-your-pc).

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
      owned by the program's hidden application window, as in the 1st to 5th Graal, and stays on top.
- [ ] The character lists hold this build's 6 characters in its order (Fung Si Yan, Nick, Mandi, ...),
      with the original's defaults. Each entry shows its head from the install's
      `heads.gif`, shrunk the way the original does it (each 2 x 2 block ANDed, which keeps the outlines).
- [ ] The program's icon is the original's.
- [ ] The game window is shaped as the original's `TAdventure` form: titled
      "Graal", 648 x 516 outside, a minimise box and no maximise box, the
      640 x 448 view and the chat field under it.
- [ ] Under Wine, screenshots of the start dialog match the original's pixel for
      pixel (open character list included).
- [ ] The original's forms, pictures, icons and strings are in `res/`, taken out by
      `scripts/realres/extract_res.py`; the program carries them itself and
      never reads the original program.

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
- [ ] Windows' scrollbars on the dialog at large display scaling (VCL
      AutoScroll) and Alt+Enter full screen.

Chat, items, weapons, enemies, level scripts, signs, saving, sound, and
the build's own character graphics (a stand-in character is drawn). This
is an early version: the comparison with the original, action by action,
comes later.

## Running it

Start `GraalB5` with no arguments for the start screen. From a
terminal: `GraalB5 --level levels/level1.graal --window`, or
`GraalB5 --server HOST:PORT --nick NAME`. `--help` lists every flag.
