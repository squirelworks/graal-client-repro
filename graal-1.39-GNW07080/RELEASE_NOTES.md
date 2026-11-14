# Graal 1.39 (GNW07080), 0.0.1

A first rebuild of the Graal 1.39 client in Delphi (Object Pascal),
for Linux and Windows. It logs in the way 1.39 did and plays a level
offline. It is early and many parts still behave like a later Graal: see
"Not yet".

**Login token: tested against the real client.** The original was run in the lab and `GNW07080` was seen in its login on the wire (traffic captured and decoded under Wine); this rebuild sends the same token.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

Apart from the start dialog and the icon, which are taken from the real
Graal.exe and compiled in, the zips hold no original Graal code, graphics,
sounds or levels. The client carries simple graphics of its own.

## What's new in v0.0.5

- [x] **Spin attack.** With the spin status (STATUS bit 0x40, from the server or the spin attack item), pressing S again while the swing still plays cuts it off and plays `spin` (13 ticks, then idle); S during the spin is ignored. Modelled on the live 2.05 and 2.22 runs; the 1.21 readme names laying items, but this build was not run for it. What the spin hits (a box round the player here) is not yet checked on the real client (#302).
- [x] **Laying items.** Hold S and press A to pick an item to lay; it shows over the head. A again with S held picks the next item, A alone lays it in front, and an arrow, S or D leaves without laying. Rupees, bombs, darts, a heart, the glove, a stock sword or shield and the spin can be laid, at the 2.05 costs; online a laid floor item is sent as `PLI_ITEMADD` (12). A custom sword or shield picture is not laid yet, and water in front is not told apart from land (#302).
- [x] **F1 shows the level's full path.** The F1 window's Current level field holds the level file's full path, as the real 1.x shows it, not the bare file name (#302).

## What's new in v0.0.4.2

- [x] **F1 Options window.** F1 opens "Options" from the build's own form (TOptions, now pulled into `res/Options.dfm` and compiled in), with the current level's file name filled in. Edit level opens the editor. The other buttons close it and do nothing yet. Linux and macOS draw the form in a window of their own.
- [x] **Default server.** The server field now starts on the rebuild's own default (listserver.txt, else `listserver.graal.in`) instead of the original's long-gone host, so the code that swapped that host out on connect is gone.
- [x] **The counts and the sword in the status display.** The rupee, bomb and arrow counts come from the digit sprites of the sprite sheet (arrays.dat sprites 268 to 277) when the state picture has no digit row (224 x 81, up to 1.37), so they show again. The player's sword picture stands beside the S button, as in the real client.
- [x] **Pictures by kind.** The picture cache keeps each name once per kind (head, body, sword, shield, hat, weapon), because each kind searches its own folders. A picture first asked for without its kind got the built-in stand-in and kept it, so an install's own picture could stay hidden behind the stand-in (in 1.33, `levels/weapons/wbomb1.gif` beside the D button).

## What's new in v0.0.4

- [x] **One Player's start.** start1.graal at x 21.5, y 28, read from the exe's own start table, then moved by the level's own script as in the original (start1.graal's playerenters puts the player at 13.5, 37.5, under Stefan).
- [x] **NPC messages and names.** White Arial Bold 20 px on a blue shadow, measured from the real client on Windows 10. Long messages wrap at the view's width, each line centred over the NPC and kept inside the view. An NPC outside the view shows no message.
- [x] **The game window's frame.** A Delphi form owned by a hidden application window (the taskbar button), sizable with the minimise and maximise boxes ($16CF0000), as the real one on Windows 10.
- [x] **Alt+Enter.** 640 x 480 full screen and back, as the original's DirectDraw view.
- [x] **The minimap.** It shows only on a level of the map's grid, so the start cave and the houses show none.
- [x] **The start dialog's scroll bars.** The scroll range counts the details panel at its full height, so on Windows 10 the dialog shows both scroll bars as the real one does.

## What's new in v0.0.3

- [x] **The real start dialog.** It opens on 1.39's own form, "Graal - The Adventure" (TConnectFrame), compiled in from the real Graal.exe with its pictures, labels and controls in their places (`res/ConnectFrame.txt`). There is no bigger window behind it.
- [x] **The real frame.** The dialog is 441 x 349 outside and centred on the screen. It has a sizable frame with the minimise box and a greyed maximise box, as the form's BorderIcons give it. When the frame leaves the form too small, scroll bars come up, as on Windows 10.
- [x] **Modes, as the real one switches them.** One Player shows the Nick Name row. One Player Online shows the whole panel (Server, Port, Account, Password, "Load head/colors from last session") over the credits. Two to Four Players show one more character list per player.
- [x] **The character list.** 29 entries (Fung Si Yan ... Sleep Koji) come from the install's headsconfig.txt, else the copy compiled in (`res/characters.txt`). Each is drawn with its head's front at half size, owner-drawn as the original. Fung Si Yan is the default, and Nick, Mandi and Bad Max are the defaults for players 2 to 4. The pick sets the player's head and five body colours in the game.
- [x] **Language list.** It lists the install's language files, by name, with English picked.
- [x] **Online defaults.** The server field held the original's default host and the port is 14900, as the real one fills them. graalconfig.txt (`serveraddr=`, `serverport=`) or listserver.txt fills them instead. That host is gone, so it stood for the community server.
- [x] **Icon.** The program's icon is MAINICON, taken from the real exe.
- [x] **Game window.** It is titled "Graal" (TAdventure's caption), with a 640 x 480 client, as the real 1.39 opens it. That is checked under Wine.
- Stress tested before release: a long soak with several players walking
  between levels, others connecting and dropping again and again, and a
  level with 80 scripted NPCs, with no crash, error or memory growth.

## Downloads

| Zip | Runs on | Window |
|---|---|---|
| `…-linux.zip` | Linux x86-64 | X11 |
| `…-windows.zip` | Windows, 32-bit | GDI |

Each zip has `Graal139` (the client) and the build's README. The test
programs are built and run on every release but no longer shipped.

On Windows the first start may show **"Windows protected your PC"**. That
is SmartScreen meeting an unsigned program it has not seen before, not a
virus warning. Either click **More info**, then **Run anyway** (once), or
unblock the zip before you extract it: right-click it, **Properties**,
tick **Unblock**, **OK**. Then nothing in the folder is asked about again.
See [Windows says "Windows protected your PC"](https://github.com/squirelworks/graal-client-repro#windows-says-windows-protected-your-pc).

## Where to put your Graal files

Put `Graal139` in a folder and copy the contents of your own 1.39 install
next to it: `levels/`, `pics1.png` and the rest, as the install has them.
The program reads only that folder. Without them it uses its own graphics
and starter level.

## What works

- The login line: id 0, `GNW07080`, account and password, sent as one
  zlib frame with no cipher.
- The level the server sends (the board first, then its name), other
  players, walking, links and warps.
- A start screen: Training plays `levels/start1.graal` from your install
  (or the built-in level), and Start offers one server address to connect
  to, as 1.39 had no server list. It is `listserver.graal.in:14923`
  until you set `serveraddr=` and `serverport=` in `graalconfig.txt` next
  to the program.

## Not yet

Most of the game still follows a later Graal: the script commands, the
item list, sound and the editor have not been checked against 1.39.
No local 2 to 4 player modes, no UDP, no options page.

- [ ] Two to Four Players on one keyboard. The modes are offered, but they play as One Player.
- [ ] The status bar as 1.39 draws it. The rebuild still draws a later HUD.
- [ ] The other forms in the exe: More options, Controls, and the editor dialogs (F1's Options window is drawn, its other buttons do nothing yet).
- [ ] The nick and "Load head/colors from last session" kept in HKCU\Software\Graal\Client.
- [ ] The dialog's text uses Liberation Sans for MS Sans Serif, so a line can break one word apart from the real one.
- [ ] The real message boxes (connection failed and the like).
- [ ] A self-contained exe. The start dialog, icon and character list are compiled in, but the levels, heads, sprites and sounds are still read from the install folder rather than compiled in with the folder as a fallback.
- [ ] The sword picture beside S, and its power in the original's large digits.
- [ ] The vertical place of NPC messages and names is the rebuild's; only their font, wrapping and centring are taken from the original.

## Checks behind this release

The test programs run with range and overflow checks and the heap tracer
and must end with no unfreed memory; they include a fuzz run of the
receive path. CI also logs two of these clients into seihai-gserver on
loopback, has the second see the first, and walks one through a level
link.
