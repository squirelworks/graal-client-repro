# Graal 1.1.9 Gold Edition (19990211)

A rebuild of the classic Graal 1.1.9 "Gold Edition" client in Delphi
(Object Pascal). Like the original it is a windowed program: it opens on
the game mode, One Player for your own levels or One Player Online with a
connect dialog. This is an early, hit-or-miss first release.

**Login token: none.** The original sends no version token, so there is nothing to check here.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

Apart from the start dialog and the icon, which are taken from the real
Graal.exe and compiled in, these zips hold no original Graal code, graphics,
sounds or levels. The program carries small original default graphics and a starter level of its
own, so it runs as it is. Put it at the top of a 1.1.9 install you own (or
keep a `graal-assets/` folder next to it, or point it at one with
`--data DIR`) and the install's tiles and levels take their place.

## What's new in v0.0.5

- [x] **Spin attack.** With the spin status (STATUS bit 0x40, from the server or the spin attack item), pressing S again while the swing still plays cuts it off and plays `spin` (13 ticks, then idle); S during the spin is ignored. Modelled on the live 2.05 and 2.22 runs; the 1.21 readme names laying items, but this build was not run for it. What the spin hits (a box round the player here) is not yet checked on the real client (#302).
- [x] **Laying items.** Hold S and press A to pick an item to lay; it shows over the head. A again with S held picks the next item, A alone lays it in front, and an arrow, S or D leaves without laying. Rupees, bombs, darts, a heart, the glove, a stock sword or shield and the spin can be laid, at the 2.05 costs; online a laid floor item is sent as `PLI_ITEMADD` (12). A custom sword or shield picture is not laid yet, and water in front is not told apart from land (#302).
- [x] **F1 shows the level's full path.** The F1 window's Current level field holds the level file's full path, as the real 1.x shows it, not the bare file name (#302).

## What's new in v0.0.4.2

- [x] **Minimap only on the map.** The minimap is drawn only on a level of its grid, as the real client does: a server's level off the map (or a house or cave) shows none. Before, it was drawn on every level.
- [x] **Asleep at the start.** One Player starts asleep in the left bed, only the head showing, as the real client does; the first key wakes the player, who gets up without acting on that press.
- [x] **F1 Options window.** F1 opens "Options" from the build's own form (TOptions), with the current level's file name filled in. F6 opens it too, as in this build. Edit level opens the editor. The other buttons close it and do nothing yet. Linux and macOS draw the form in a window of their own.
- [x] **Default server.** The server field now starts on the rebuild's own default (listserver.txt, else `listserver.graal.in`) instead of the original's long-gone host, so the code that swapped that host out on connect is gone.
- [x] **Pictures by kind.** The picture cache keeps each name once per kind (head, body, sword, shield, hat, weapon), because each kind searches its own folders. A picture first asked for without its kind got the built-in stand-in and kept it, so an install's own picture could stay hidden behind the stand-in (in 1.33, `levels/weapons/wbomb1.gif` beside the D button).

## What's new in v0.0.4

- Rebuilt from the latest code; the changes for this client are listed here as they land.

## What's new in v0.0.3

- [x] **The real start dialog.** It opens on 1.1.9's own form, "Graal - The Adventure" (TConnectFrame), compiled in from the real Graal.exe with its pictures, labels and controls in their places (`res/ConnectFrame.txt`). There is no bigger window behind it.
- [x] **The real frame.** The dialog is 441 x 348 outside and centred on the screen. It has a sizable frame with the minimise box and a greyed maximise box, as the form's BorderIcons give it. When the frame leaves the form too small, scroll bars come up, as on Windows 10.
- [x] **Modes, as the real one switches them.** One Player, One Player Online, Two Players, Three Players, Four Players. One Player shows no panel. One Player Online shows Nick Name, Server and Port. Two or more players show one more character list per player.
- [x] **The character list.** 23 entries (Fung Si Yan ... Pach Soldier) come from the exe's own table (1.1 has no headsconfig.txt). Each is drawn with its head's front at half size, owner-drawn as the original. Fung Si Yan is the default, and Nick, Mandi and Bad Max are the defaults for players 2 to 4. The pick sets the player's head and five body colours in the game.
- [x] **Heads from heads.gif.** The heads come from the install's heads.gif, where head N is column N, in the dialog and in the game.
- [x] **Online defaults.** The server field held the original's default host and the port is 14802, as the real one fills them. graalconfig.txt (`serveraddr=`, `serverport=`) or listserver.txt fills them instead. That host is gone, so it stood for the community server.
- [x] **Icon.** The program's icon is MAINICON, taken from the real exe.
- [x] **Game window.** It is titled "Graal" (TAdventure's caption), with a 640 x 448 client, as the real 1.1.9 opens it. That is checked under Wine.
- [x] **One Player start level.** One Player opens house1.graal, as the real one does.
- Stress tested before release: a long soak with several players on one
  relay and others connecting and dropping again and again, with no crash,
  error or memory growth.
- [ ] The start dialog is this build's own. Its form (`TConnectFrame`) is taken
      from the original program and compiled in: the mode list (One Player, One Player Online and Two to Four Players),
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

Each zip has `Graal119` (the client) and the build's README. The test
programs are built and run on every release but no longer shipped.

On Windows the first start may show **"Windows protected your PC"**. That
is SmartScreen meeting an unsigned program it has not seen before, not a
virus warning. Either click **More info**, then **Run anyway** (once), or
unblock the zip before you extract it: right-click it, **Properties**,
tick **Unblock**, **OK**. Then nothing in the folder is asked about again.
See [Windows says "Windows protected your PC"](https://github.com/squirelworks/graal-client-repro#windows-says-windows-protected-your-pc).

## What works

- The 1.1.9 relay link: two links to the game server, the `Graal8` game
  and a room per level, pairing with the players met there, and their
  positions, nicknames, colours, chat lines and board changes.
- The connect dialog, filled with `listserver.graal.in` port 14802
  (another can be named in `listserver.txt`).
- One Player on `levels/level1.graal`: walking, collision and level links
  on the install's tiles.

## Running it

```
Graal119                                    # game mode and connect dialog
Graal119 --level levels/level1.graal        # One Player
Graal119 --server HOST:14802 --nick NAME    # One Player Online
```

Arrow keys walk, Esc leaves the game.

## Not yet

- [ ] The player is drawn with the rebuild's stand-in animations, not the
      build's own sprite sheet and the chosen head.
- [ ] Two to Four Players start the one-player game; the local multiplayer modes
      are not rebuilt.
- [ ] The character picked in the dialog is not yet drawn in the game.

Smoke-tested only. The original's status bar, sprites and letters sheets,
Two and Four Players, save games and web levels are not done yet.

- [ ] Two to Four Players on one keyboard. The modes are offered, but they play as One Player.
- [ ] The other forms in the exe: More options, Controls, and the editor dialogs (F1's Options window is drawn, its other buttons do nothing yet).
- [ ] The nick and "Load head/colors from last session" kept in HKCU\Software\Graal\Client.
- [ ] The dialog's text uses Liberation Sans for MS Sans Serif, so a line can break one word apart from the real one.
- [ ] The real message boxes (connection failed and the like).
- [ ] A self-contained exe. The start dialog, icon and character list are compiled in, but the levels, heads, sprites and sounds are still read from the install folder rather than compiled in with the folder as a fallback.
