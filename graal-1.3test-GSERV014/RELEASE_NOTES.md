# Graal 1.3 test (GSERV014), 0.0.1

A first rebuild of the Graal 1.3 test client in Delphi (Object Pascal),
for Linux and Windows. It logs in the way 1.3 test did and plays a level
offline. It is early and many parts still behave like a later Graal: see
"Not yet".

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

Apart from the start dialog and the icon, which are taken from the real
Graal13.exe and compiled in, the zips hold no original Graal code, graphics,
sounds or levels. The client carries simple graphics of its own.

## What's new in v0.0.4

- [x] **The A, S and D buttons.** They are the three lettered buttons of the install's state picture, side by side as 1.3test's 224 x 81 state picture holds them. The rebuild no longer draws a letter of its own over the D button (which read as a "B").
- [x] **One Player's start.** house1.graal at x 21.5, y 28, read from the exe's own start table (the level and position for players one to four).
- [x] **NPC messages and names.** White Arial Bold 20 px on a blue shadow, measured from the real client on Windows 10. Long messages wrap at the view's width, each line centred over the NPC and kept inside the view. An NPC outside the view shows no message.
- [x] **The game window's frame.** A Delphi form owned by a hidden application window (the taskbar button), sizable with the minimise and maximise boxes ($16CF0000), as the real one on Windows 10.
- [x] **Alt+Enter.** 640 x 480 full screen and back, as the original's DirectDraw view.
- [x] **The minimap.** It shows only on a level of the map's grid, so the start cave and the houses show none.
- [x] **The start dialog's scroll bars.** The scroll range counts the details panel at its full height, so on Windows 10 the dialog shows both scroll bars as the real one does.

## What's new in v0.0.3

- [x] **The real start dialog.** It opens on 1.3test's own form, "Graal - The Adventure" (TConnectFrame), compiled in from the real Graal13.exe with its pictures, labels and controls in their places (`res/ConnectFrame.txt`). There is no bigger window behind it.
- [x] **The real frame.** The dialog is 441 x 349 outside and centred on the screen. It has a sizable frame with the minimise box and a greyed maximise box, as the form's BorderIcons give it. When the frame leaves the form too small, scroll bars come up, as on Windows 10.
- [x] **Modes, as the real one switches them.** One Player shows the Nick Name row. One Player Online shows the whole panel (Server, Port, Account, Password, "Load head/colors from last session") over the credits. Two to Four Players show one more character list per player.
- [x] **The character list.** 29 entries (Fung Si Yan ... Sleep Koji) come from the install's headsconfig.txt, else the copy compiled in (`res/characters.txt`). Each is drawn with its head's front at half size, owner-drawn as the original. Fung Si Yan is the default, and Nick, Mandi and Bad Max are the defaults for players 2 to 4. The pick sets the player's head and five body colours in the game.
- [x] **Language list.** It lists the install's language files, by name, with English picked.
- [x] **Online defaults.** The server field holds www.graalonline.com and the port is 14804, as the real one fills them. graalconfig.txt (`serveraddr=`, `serverport=`) or listserver.txt fills them instead. www.graalonline.com is gone, so it stands for the community server.
- [x] **Icon.** The program's icon is MAINICON, taken from the real exe.
- [x] **Game window.** It is titled "Graal" (TAdventure's caption), with a 640 x 472 client, as the real 1.3test opens it. That is checked under Wine.
- Stress tested before release: a long soak with several players walking
  between levels, others connecting and dropping again and again, and a
  level with 80 scripted NPCs, with no crash, error or memory growth.

## Downloads

| Zip | Runs on | Window |
|---|---|---|
| `…-linux.zip` | Linux x86-64 | X11 |
| `…-windows.zip` | Windows, 32-bit | GDI |

Each zip has `Graal13test` (the client) and the build's README. The test
programs are built and run on every release but no longer shipped.

On Windows the first start may show **"Windows protected your PC"**. That
is SmartScreen meeting an unsigned program it has not seen before, not a
virus warning. Either click **More info**, then **Run anyway** (once), or
unblock the zip before you extract it: right-click it, **Properties**,
tick **Unblock**, **OK**. Then nothing in the folder is asked about again.
See [Windows says "Windows protected your PC"](https://github.com/squirelworks/graal-client-repro#windows-says-windows-protected-your-pc).

## Where to put your Graal files

Put `Graal13test` in a folder and copy the contents of your own 1.3 test install
next to it: `levels/`, `pics1.png` and the rest, as the install has them.
The program reads only that folder. Without them it uses its own graphics
and starter level.

## What works

- The login line: id 0, `GSERV014`, account and password, sent as one
  zlib frame with no cipher.
- The level the server sends (the board first, then its name), other
  players, walking, links and warps.
- A start screen: Training plays `levels/start1.graal` from your install
  (or the built-in level), and Start offers one server address to connect
  to, as 1.3 test had no server list. It is `listserver.graal.in:14923`
  until you set `serveraddr=` and `serverport=` in `graalconfig.txt` next
  to the program.

## Not yet

Most of the game still follows a later Graal: the script commands, the
item list, sound and the editor have not been checked against 1.3 test.
No local 2 to 4 player modes, no UDP, no options page.

- [ ] Two to Four Players on one keyboard. The modes are offered, but they play as One Player.
- [ ] The other forms in the exe: the F1 options window, More options, and the editor dialogs.
- [ ] The nick and "Load head/colors from last session" kept in HKCU\Software\Graal\Client.
- [ ] The dialog's text uses Liberation Sans for MS Sans Serif, so a line can break one word apart from the real one.
- [ ] The real message boxes (connection failed and the like).
- [ ] A self-contained exe. The start dialog, icon and character list are compiled in, but the levels, heads, sprites and sounds are still read from the install folder rather than compiled in with the folder as a fallback.
- [ ] The rest of the status bar: the sword picture beside S, and the counters in the original's own digits.
- [ ] Lying in bed at the start, as the original shows the player in house1.
- [ ] The vertical place of NPC messages and names is the rebuild's; only their font, wrapping and centring are taken from the original.

## Checks behind this release

The test programs run with range and overflow checks and the heap tracer
and must end with no unfreed memory; they include a fuzz run of the
receive path. CI also logs two of these clients into seihai-gserver on
loopback, has the second see the first, and walks one through a level
link.
