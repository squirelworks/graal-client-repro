# Graal 1.1 (19990214)

A rebuild of the classic Graal 1.1 client in Delphi
(Object Pascal). Like the original it is a windowed program: it opens on
the game mode, One Player for your own levels or One Player Online with a
connect dialog. This is an early, hit-or-miss first release.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

Apart from the start dialog and the icon, which are taken from the real
Graal.exe and compiled in, these zips hold no original Graal code, graphics,
sounds or levels. The program carries small original default graphics and a starter level of its
own, so it runs as it is. Put it at the top of a 1.1 install you own (or
keep a `graal-assets/` folder next to it, or point it at one with
`--data DIR`) and the install's tiles and levels take their place.

## What's new in v0.0.3

- [x] **The real start dialog.** It opens on 1.1's own form, "Graal - The Adventure" (TConnectFrame), compiled in from the real Graal.exe with its pictures, labels and controls in their places (`res/ConnectFrame.txt`). There is no bigger window behind it.
- [x] **The real frame.** The dialog is 441 x 348 outside and centred on the screen. It has a sizable frame with the minimise box and a greyed maximise box, as the form's BorderIcons give it. When the frame leaves the form too small, scroll bars come up, as on Windows 10.
- [x] **Modes, as the real one switches them.** One Player, One Player Online, Two Players. One Player shows no panel. One Player Online shows Nick Name, Server and Port. The Server field is greyed, as in 1.1. Two or more players show one more character list per player.
- [x] **The character list.** 23 entries (Fung Si Yan ... Pach Soldier) come from the exe's own table (1.1 has no headsconfig.txt). Each is drawn with its head's front at half size, owner-drawn as the original. Fung Si Yan is the default, and Nick, Mandi and Bad Max are the defaults for players 2 to 4. The pick sets the player's head and five body colours in the game.
- [x] **Heads from heads.gif.** The heads come from the install's heads.gif, where head N is column N, in the dialog and in the game.
- [x] **Online defaults.** The server field holds www.graalonline.com and the port is 14802, as the real one fills them. graalconfig.txt (`serveraddr=`, `serverport=`) or listserver.txt fills them instead. www.graalonline.com is gone, so it stands for the community server.
- [x] **Icon.** The program's icon is MAINICON, taken from the real exe.
- [x] **Game window.** It is titled "Graal" (TAdventure's caption), with a 640 x 448 client, as the real 1.1 opens it. That is checked under Wine.
- [x] **One Player start level.** One Player opens house1.graal, as the real one does.
- Stress tested before release: a long soak with several players on one
  relay and others connecting and dropping again and again, with no crash,
  error or memory growth.

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

Smoke-tested only. The original's status bar, sprites and letters sheets,
Two Players, save games and web levels are not done yet.

- [ ] Two to Four Players on one keyboard. The modes are offered, but they play as One Player.
- [ ] The status bar as 1.1 draws it. The rebuild still draws a later HUD.
- [ ] One Player's start position and camera.
- [ ] The other forms in the exe: the F1 options window, More options, and the editor dialogs.
- [ ] Alt+Enter full screen.
- [ ] The nick and "Load head/colors from last session" kept in HKCU\Software\Graal\Client.
- [ ] The dialog's text uses Liberation Sans for MS Sans Serif, so a line can break one word apart from the real one.
- [ ] The real message boxes (connection failed and the like).
- [ ] A self-contained exe. The start dialog, icon and character list are compiled in, but the levels, heads, sprites and sounds are still read from the install folder rather than compiled in with the folder as a fallback.
