# Graal 1.41 rev 1 (GNW13110)

A rebuild of the classic Graal 1.41 rev 1 client in Delphi (Object Pascal).
Like the original it is a windowed program: it opens on a start window with
the game mode, the nick name and Start. This is an early, hit-or-miss first
release.

**Login token: tested against the real client.** The original was run in the lab and `GNW13110` was seen in its login on the wire (Wine lab run, 2026-11-04); this rebuild sends the same token.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

Apart from the start dialog and the icon, which are taken from the real
Graal.exe and compiled in, these zips hold no original Graal code, graphics,
sounds or levels. The program carries small original default graphics and a starter level of its
own, so it runs as it is. Put it at the top of a 1.41 install you own (or
keep a `graal-assets/` folder next to it, or point it at one with
`--data DIR`) and the install's tiles, heads, bodies and levels take their
place.

## What's new in v0.0.5

- [x] **Seihai secure login (optional, off by default).** With `--secure-login auto` (or `required`, or `secure_login.txt` in the settings folder), the account and password go sealed to a Seihai game server (`SEI00001`), after the server's key is checked and pinned. Servers that do not know it get the original login under `auto`. Off, the login is byte for byte the original's. This is not in the original game.
- [x] **Checked against the unpatched original.** The copy this rebuild was first made from had been patched for graal.in. Of the two other 1.41r1 copies held, the one in `Graal v1.41r1.rar` is the unpatched original (listserver `www.graalonline.com`, port 14910). The token, the cipher, the forms and the icon are the same bytes in all copies, so they stay. The server list window is titled "Graalonline.com Server List" again, as in the original. The default listserver stays `listserver.graal.in` on 14923, because the original's is gone.
- [x] **F1 shows the level's full path.** The F1 window's Current level field holds the level file's full path, as the real 1.x shows it, not the bare file name (#302).

## What's new in v0.0.4.2

- [x] **F1 Help window.** F1 opens "Help" from the build's own form (TOptions): the save games and level editing groups with the current level, Debugger, Playerlist, Serverlist, General options, Controls and Close. It is a real dialog on Windows and drawn elsewhere. Edit level opens the editor; the other buttons close it and do nothing yet.
- [x] **The counts and the sword in the status display.** The rupee, bomb and arrow counts come from the digit sprites of the sprite sheet (arrays.dat sprites 268 to 277) when the state picture has no digit row (224 x 81, up to 1.37), so they show again. The player's sword picture stands beside the S button, as in the real client.
- [x] **Pictures by kind.** The picture cache keeps each name once per kind (head, body, sword, shield, hat, weapon), because each kind searches its own folders. A picture first asked for without its kind got the built-in stand-in and kept it, so an install's own picture could stay hidden behind the stand-in (in 1.33, `levels/weapons/wbomb1.gif` beside the D button).

## What's new in v0.0.4

- [x] **One Player's start.** start1.graal at x 21.5, y 28, read from the exe's own start table, then moved by the level's own script as in the original (start1.graal's playerenters puts the player at 13.5, 37.5, under Stefan).
- [x] **NPC messages and names.** White Arial Bold 20 px on a blue shadow, measured from the real client on Windows 10. Long messages wrap at the view's width, each line centred over the NPC and kept inside the view. An NPC outside the view shows no message.
- [x] **The game window's frame.** A Delphi form owned by a hidden application window (the taskbar button), sizable with the minimise and maximise boxes ($16CF0000), as the real one on Windows 10.
- [x] **Alt+Enter.** 640 x 480 full screen and back, as the original's DirectDraw view.
- [x] **The minimap.** It shows only on a level of the map's grid, so the start cave and the houses show none.

## What's new in v0.0.3

- [x] **The real start dialog.** It opens on 1.41r1's own form, "Graal - The Adventure" (TConnectFrame), compiled in from the real Graal.exe with its pictures, labels and controls in their places (`res/ConnectFrame.txt`). There is no bigger window behind it.
- [x] **The real frame.** The dialog is 501 x 357 outside and centred on the screen. It has a sizable frame with the minimise box and a greyed maximise box, as the form's BorderIcons give it. When the frame leaves the form too small, scroll bars come up, as on Windows 10.
- [x] **Modes.** One Player, One Player Online, Two Players, Three Players, Four Players. The mode picked at start is graalconfig.txt's `gamemode=` (the install's says One Player Online).
- [x] **Words from the language file.** The labels, mode names and title come from `languages/language<Name>.txt` (StartScreen-...), and they change with the Language list, as in 1.41.
- [x] **Several players.** Two to Four Players draw each player's head beside the Character list. A click on a head picks the player the list is for, as the language file's hint says.
- [x] **Server list.** Start in One Player Online goes to the server list, where the account and password are typed.
- [x] **The character list.** 29 entries (Fung Si Yan ... Sleep Koji) come from the install's headsconfig.txt, else the copy compiled in (`res/characters.txt`). Each is drawn with its head's front at half size, owner-drawn as the original. Fung Si Yan is the default, and Nick, Mandi and Bad Max are the defaults for players 2 to 4. The pick sets the player's head and five body colours in the game.
- [x] **Language list.** It lists the install's language files, by name, with English picked.
- [x] **Icon.** The program's icon is MAINICON, taken from the real exe.
- [x] **Game window.** It is titled "Graal" (TAdventure's caption), with a 640 x 480 client, as the real 1.41r1 opens it. That is checked under Wine.
- Stress tested before release: a long soak with several players walking
  between levels, others connecting and dropping again and again, and a
  level with 80 scripted NPCs, with no crash, error or memory growth.

## Downloads

| Zip | Runs on | Window |
|---|---|---|
| `…-linux.zip` | Linux x86-64 | X11 |
| `…-windows.zip` | Windows, 32-bit | GDI |

Each zip has `Graal141` (the client) and the build's README. The test
programs are built and run on every release but no longer shipped.

On Windows the first start may show **"Windows protected your PC"**. That
is SmartScreen meeting an unsigned program it has not seen before, not a
virus warning. Either click **More info**, then **Run anyway** (once), or
unblock the zip before you extract it: right-click it, **Properties**,
tick **Unblock**, **OK**. Then nothing in the folder is asked about again.
See [Windows says "Windows protected your PC"](https://github.com/squirelworks/graal-client-repro#windows-says-windows-protected-your-pc).

## What works

- The 1.41 login: gen-3 cipher, zlib framing, token `GNW13110`, the login
  props with the head as a number, and no language packet.
- The server list from `listserver.graal.in` (port 14923; another can be
  named in `listserver.txt`), with the account and password on the list
  page.
- One Player: the install's `start1.graal`, offline.
- Levels (`.graal`, `.nw`), walking, collision, level links and warps, NPCs,
  items, combat, signs, the map and the level editor.

## Running it

```
Graal141                                                   # start window
GRAAL_PW=... Graal141 --server HOST:PORT --account NAME
Graal141 --level levels/start1.graal                       # offline
```

Arrow keys walk, Esc leaves the game. `Graal141 --help` lists every flag.

## Not yet

This release has only been smoke-tested against the original: start window
and login. Two to four players on one computer, save games, the options
window and drawing from the 1.41 sprite sheet are not done.

- [ ] Two to Four Players on one keyboard. The modes are offered, but they play as One Player.
- [ ] The status bar as 1.41r1 draws it. The rebuild still draws a later HUD.
- [ ] The other forms in the exe: More options and the editor dialogs.
- [ ] The nick and "Load head/colors from last session" kept in HKCU\Software\Graal\Client.
- [ ] The dialog's text uses Liberation Sans for MS Sans Serif, so a line can break one word apart from the real one.
- [ ] The real message boxes (connection failed and the like).
- [ ] The real server list form (TServerListFrame). The rebuild's own list page is shown instead.
- [ ] A self-contained exe. The start dialog, icon and character list are compiled in, but the levels, heads, sprites and sounds are still read from the install folder rather than compiled in with the folder as a fallback.
- [ ] The sword picture beside S, and its power in the original's large digits.
- [ ] The vertical place of NPC messages and names is the rebuild's; only their font, wrapping and centring are taken from the original.
