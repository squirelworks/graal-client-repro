# Graal 1.21 (GSERV007), 0.0.1

A first rebuild of the Graal 1.21 client in Delphi (Object Pascal),
for Linux and Windows. It logs in the way 1.21 did and plays a level
offline. It is early and many parts still behave like a later Graal: see
"Not yet".

**Login token: tested against the real client.** The original was run in the lab and `GSERV007` was seen in its login on the wire (lab captures); this rebuild sends the same token.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

Apart from the start dialog and the icon, which are taken from the real
Graal.exe and compiled in, the zips hold no original Graal code, graphics,
sounds or levels. The client carries simple graphics of its own.

## What's new in v0.0.5

- [x] **Minimap only on the map.** The minimap is drawn only on a level of its grid, as the real client does: a server's level off the map (or a house or cave) shows none. Before, it was drawn on every level.
- [x] **Asleep at the start.** One Player starts asleep in the left bed, only the head showing, as the real 1.1.9 and 1.28 beta 2 do (1.21 itself was not captured); the first key wakes the player, who gets up without acting on that press.
- [x] **F1 Options window.** F1 opens "Options" from the build's own form (TOptions), with the current level's file name filled in. Edit level opens the editor. The other buttons close it and do nothing yet. Linux and macOS draw the form in a window of their own.
- [x] **Default server.** The server field now starts on the rebuild's own default (listserver.txt, else `listserver.graal.in`) instead of the original's long-gone host, so the code that swapped that host out on connect is gone.
- [x] **Other players.** OTHERPLPROPS reads the one-byte player id 1.21 sends before the props (the two-byte id starts with 1.36), so another player's props are no longer read one byte off.
- [x] **Pictures by kind.** The picture cache keeps each name once per kind (head, body, sword, shield, hat, weapon), because each kind searches its own folders. A picture first asked for without its kind got the built-in stand-in and kept it, so an install's own picture could stay hidden behind the stand-in (in 1.33, `levels/weapons/wbomb1.gif` beside the D button).

## What's new in v0.0.4

- Rebuilt from the latest code; the changes for this client are listed here as they land.

## What's new in v0.0.3

- [x] **The real start dialog.** It opens on 1.21's own form, "Graal - The Adventure" (TConnectFrame), compiled in from the real Graal.exe with its pictures, labels and controls in their places (`res/ConnectFrame.txt`). There is no bigger window behind it.
- [x] **The real frame.** The dialog is 441 x 351 outside and centred on the screen. It has a sizable frame with the minimise box and a greyed maximise box, as the form's BorderIcons give it. When the frame leaves the form too small, scroll bars come up, as on Windows 10.
- [x] **Modes, as the real one switches them.** One Player, One Player Online, Two Players, Three Players, Four Players. One Player shows no panel. One Player Online shows Nick Name, Server and Port. Two or more players show one more character list per player.
- [x] **The character list.** 28 entries (Fung Si Yan ... Squall) come from the install's headsconfig.txt, else the copy compiled in (`res/characters.txt`). Each is drawn with its head's front at half size, owner-drawn as the original. Fung Si Yan is the default, and Nick, Mandi and Bad Max are the defaults for players 2 to 4. The pick sets the player's head and five body colours in the game.
- [x] **Online defaults.** The server field held the original's default host and the port is 14804, as the real one fills them. graalconfig.txt (`serveraddr=`, `serverport=`) or listserver.txt fills them instead. That host is gone, so it stood for the community server.
- [x] **Icon.** The program's icon is MAINICON, taken from the real exe.
- [x] **Game window.** It is titled "Graal" (TAdventure's caption), with a 640 x 472 client, as the real 1.21 opens it. That is checked under Wine.
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
      original (this build's own 28 characters when there is none). Each entry
      shows its head from its own head file, `heads/headN.gif`.
- [ ] The program's icon is the original's.
- [ ] The game window is shaped as the original's `TAdventure` form.
- [ ] Under Wine, screenshots of the start dialog match the original's pixel for
      pixel (online panel included).
- [ ] The original's forms, pictures, icons and strings are in `res/`, taken out by
      `scripts/realres/extract_res.py`; the program carries them itself and
      never reads the original program.
- [ ] Made from the real 1.21 program, recovered from the InstallShield package's
      `_SETUP.1` archive with `scripts/realres/is3x.py` (its MD5 matches the README's).
- [ ] The game window is a `TAdventure` owned by the hidden application window, with the original's styles and a 640 x 448 client plus the 24-pixel chat field.
- [ ] One Player starts in `house1.graal` at 21.5, 28, the first player's spot from the original's start table (the bed).
- [ ] The status display is drawn from the install's own `state.gif`: the A, S and D buttons with the sword and bomb beside them, the rupee, bomb and arrow counts in the digits of `sprites.gif`, and the hearts, each piece where the original draws it.
- [ ] Alt+Enter switches to 640 x 480 full screen (a topmost pop-up over the whole screen) and back, as the original does.

## Downloads

| Zip | Runs on | Window |
|---|---|---|
| `…-linux.zip` | Linux x86-64 | X11 |
| `…-windows.zip` | Windows, 32-bit | GDI |

Each zip has `Graal121` (the client) and the build's README. The test
programs are built and run on every release but no longer shipped.

On Windows the first start may show **"Windows protected your PC"**. That
is SmartScreen meeting an unsigned program it has not seen before, not a
virus warning. Either click **More info**, then **Run anyway** (once), or
unblock the zip before you extract it: right-click it, **Properties**,
tick **Unblock**, **OK**. Then nothing in the folder is asked about again.
See [Windows says "Windows protected your PC"](https://github.com/squirelworks/graal-client-repro#windows-says-windows-protected-your-pc).

## Where to put your Graal files

Put `Graal121` in a folder and copy the contents of your own 1.21 install
next to it: `levels/`, `pics1.png` and the rest, as the install has them.
The program reads only that folder. Without them it uses its own graphics
and starter level.

## What works

- The login line: id 0, `GSERV007`, account and password, sent as one
  zlib frame with no cipher.
- The level the server sends (the board first, then its name), other
  players, walking, links and warps.
- A start screen: Training plays `levels/start1.graal` from your install
  (or the built-in level), and Start offers one server address to connect
  to, as 1.21 had no server list. It is `listserver.graal.in:14923`
  until you set `serveraddr=` and `serverport=` in `graalconfig.txt` next
  to the program.

## Not yet

- [ ] The player is drawn with the rebuild's stand-in animations, not the
      build's own sprite sheet and the chosen head.
- [ ] Two to Four Players start the one-player game; the local multiplayer modes
      are not rebuilt.
- [ ] The character picked in the dialog is not yet drawn in the game.

Most of the game still follows a later Graal: the script commands, the
item list, sound and the editor have not been checked against 1.21.
No local 2 to 4 player modes, no UDP, no options page.

- [ ] Two to Four Players on one keyboard. The modes are offered, but they play as One Player.
- [ ] The other forms in the exe: More options, Controls, and the editor dialogs (F1's Options window is drawn, its other buttons do nothing yet).
- [ ] The nick and "Load head/colors from last session" kept in HKCU\Software\Graal\Client.
- [ ] The dialog's text uses Liberation Sans for MS Sans Serif, so a line can break one word apart from the real one.
- [ ] The real message boxes (connection failed and the like).
- [ ] A self-contained exe. The start dialog, icon and character list are compiled in, but the levels, heads, sprites and sounds are still read from the install folder rather than compiled in with the folder as a fallback.

## Checks behind this release

The test programs run with range and overflow checks and the heap tracer
and must end with no unfreed memory; they include a fuzz run of the
receive path. CI also logs two of these clients into seihai-gserver on
loopback, has the second see the first, and walks one through a level
link.
