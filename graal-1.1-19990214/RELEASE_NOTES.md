# Graal 1.1 (19990214)

A rebuild of the classic Graal 1.1 client in Delphi
(Object Pascal). Like the original it is a windowed program: it opens on
the game mode, One Player for your own levels or One Player Online with a
connect dialog. This is an early, hit-or-miss first release.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

These zips hold no original Graal code, game graphics, sounds or levels; the
program carries only the original's start dialog (its form, pictures and icon,
taken from the original program). The
program carries small original default graphics and a starter level of its
own, so it runs as it is. Put it at the top of a 1.1 install you own (or
keep a `graal-assets/` folder next to it, or point it at one with
`--data DIR`) and the install's tiles and levels take their place.

## What's new in v0.0.3

- The Windows program carries its original's own icon (the sword, taken from
  the original exe), so Explorer shows it as the original did.
- Stress tested before release: a long soak with several players on one
  relay and others connecting and dropping again and again, with no crash,
  error or memory growth.
- [ ] The start dialog is this build's own. Its form (`TConnectFrame`) is taken
      from the original program and compiled in: the mode list (One Player, One Player Online and Two Players),
      a character list per player, and the online panel, at the same places,
      with the same captions, pictures, fonts, colours and tab order, on the
      original's window classes and frame buttons.
- [ ] The character lists hold this build's 21 characters in its order, with the
      original's defaults. Each entry shows its head from `heads.gif`.
- [ ] The program's icon is the original's.
- [ ] The game window is shaped as the original's `TAdventure` form.
- [ ] Under Wine, screenshots of the start dialog match the original's pixel for
      pixel.
- [ ] The original's forms, pictures, icons and strings are in `res/`, taken out by
      `scripts/realres/extract_res.py`; the program carries them itself and
      never reads the original program.
- [ ] The game window is a `TAdventure` owned by the hidden application window, with the original's styles and a 640 x 448 client and no chat field.
- [ ] One Player starts in `house1.graal` at 21.5, 28, the first player's spot from the original's start table (the bed).
- [ ] The status display is drawn from the install's own `state.gif`: the big bomb, the bow, the rupee, bomb and arrow icons, the counts in the digits of `sprites.gif`, and the hearts, each piece at the pixel where the original draws it (the start shows 0 rupees, 10 bombs, 05 arrows and three hearts).
- [ ] Alt+Enter switches to 640 x 480 full screen (a topmost pop-up over the whole screen) and back, as the original does.

## Downloads

| Zip | Runs on | Window |
|---|---|---|
| `…-linux.zip` | Linux x86-64 | X11 |
| `…-windows.zip` | Windows, 32-bit | GDI |

Each zip has `Graal11` (the client) and the build's README. The test
programs are built and run on every release but no longer shipped.

On Windows the first start may show **"Windows protected your PC"**. That
is SmartScreen meeting an unsigned program it has not seen before, not a
virus warning. Either click **More info**, then **Run anyway** (once), or
unblock the zip before you extract it: right-click it, **Properties**,
tick **Unblock**, **OK**. Then nothing in the folder is asked about again.
See [Windows says "Windows protected your PC"](https://github.com/squirelworks/graal-delphi#windows-says-windows-protected-your-pc).

## What works

- The 1.1 relay link: two links to the game server, the `Graal8` game
  and a room per level, pairing with the players met there, and their
  positions, nicknames, colours, chat lines and board changes.
- The connect dialog, filled with `listserver.graal.in` port 14802
  (another can be named in `listserver.txt`).
- One Player on `levels/level1.graal`: walking, collision and level links
  on the install's tiles.

## Running it

```
Graal11                                    # game mode and connect dialog
Graal11 --level levels/level1.graal        # One Player
Graal11 --server HOST:14802 --nick NAME    # One Player Online
```

Arrow keys walk, Esc leaves the game.

## Not yet

- [ ] The player is drawn with the rebuild's stand-in animations, not the
      build's own sprite sheet and the chosen head; the F1 options window is
      not rebuilt.
- [ ] Linux and macOS keep the shared start screen; the original's dialog is
      Windows only.
- [ ] Two Players starts the one-player game; the local multiplayer mode
      is not rebuilt.
- [ ] The character picked in the dialog is not yet drawn in the game.

Smoke-tested only. The original's status bar, sprites and letters sheets,
Two Players, save games and web levels are not done yet.
