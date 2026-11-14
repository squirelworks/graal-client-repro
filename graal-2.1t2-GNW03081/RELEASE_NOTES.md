# Graal 2.1 test 2 (GNW03081)

A rebuild of the classic Graal 2.1 test 2 client in Delphi (Object Pascal).
Like the original it is a windowed program: it opens on a start window with
Training, the server list from the listserver, and login. This is an early,
hit-or-miss first release.

**Login token: tested against the real client.** The original was run in the lab and `GNW03081` was seen in its login on the wire (Wine lab run, 2026-11-04); this rebuild sends the same token.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

The program carries what the original's own `Graal.exe` carries: the start
window and server list forms, their art and buttons, its offline Training
levels and the Graal head icon. It also carries the files of the 2.1 test 2
install that the game reads: the tile and sprite sheets, the heads, bodies,
swords and shields, the ganis, the Training and start levels, the maps, the
sounds and the language files. So it runs alone in an empty folder and looks
like the original. (The 2.1 test 2 install at hand had no pics1.png; the
tiles are NewMain 26's.) Put it at the top of a Graal install you own (or
keep a `graal-assets/` folder next to it, or point it at one with `--data
DIR`) and the install's files come first.

## What's new in v0.0.5

- [x] **Spin attack.** With the spin status (STATUS bit 0x40, from the server or the spin attack item), pressing S again while the swing still plays cuts it off and plays `spin` (13 ticks, then idle); S during the spin is ignored. Modelled on the live 2.05 and 2.22 runs. What the spin hits (a box round the player here) is not yet checked on the real client (#302).
- [x] **Laying items.** Hold S and press A to pick an item to lay; it shows over the head. A again with S held picks the next item, A alone lays it in front, and an arrow, S or D leaves without laying. Rupees, bombs, darts, a heart, the glove, a stock sword or shield and the spin can be laid, at the 2.05 costs; online a laid floor item is sent as `PLI_ITEMADD` (12). A custom sword or shield picture is not laid yet, and water in front is not told apart from land (#302).
- [x] **F1 worded by the language file.** The Help window takes its title and captions from the install's `Options` keys, as the real 2.1 test does ("&Playerlist (F7)", "Se&rverlist (F8)"), not the form's title-cased "Player List" (#302, lab on Windows XP, 2026-11-13).

## What's new in v0.0.4.2

- [x] **Minimap only on the map.** The minimap is drawn only on a level of its grid, as the real client does: a server's level off the map (or a house or cave) shows none. Before, it was drawn on every level.
- [x] **F1 Help window.** F1 opens "Help" from the build's own form (TOptions): the "Game windows" group and Close. It is a real dialog on Windows and drawn elsewhere. Edit level opens the editor; the other buttons close it and do nothing yet.
- [x] **Neutral window titles.** The server list window is titled "Server List", not the original's caption, which named the original's host (#191).
- [x] **Pictures by kind.** The picture cache keeps each name once per kind (head, body, sword, shield, hat, weapon), because each kind searches its own folders. A picture first asked for without its kind got the built-in stand-in and kept it, so an install's own picture could stay hidden behind the stand-in (in 1.33, `levels/weapons/wbomb1.gif` beside the D button).

## What's new in v0.0.4

- The A, S and D key letters are drawn the way the original draws them:
  Windows text in the font it asks for (Helvetica, which Windows shows as
  Arial), bold, white, over a black shadow one pixel down and right, at the
  original's places on the tags. Before this they used the rebuild's own small
  block letters, and the S looked like a B.
- The little Q over the D tag is drawn, as on the original.
- The sword power number and the names under characters are in Tempus Sans
  ITC, bold, white over a blue shadow, as the original draws them. The font is
  read from the install's own tempsitc.ttf, as the original loads it. Without
  that file the program uses Arial, as Windows does.

## What's new in v0.0.3

- The Windows program carries its original's own icon (the Graal head, taken
  from the original exe), so Explorer shows it as the original did.
- Stress tested before release: a long soak with several players walking
  between levels, others connecting and dropping again and again, and a
  level with 80 scripted NPCs, with no crash, error or memory growth.
- The start window and the server list are the original's own: laid out from
  the forms inside the original exe, with its background pictures, buttons,
  captions and colours compiled into the program, so it needs no original
  exe beside it.
- The launcher window is the dialog itself, sized to its picture, with only
  the close button, as on the original.
- The server list shows the listserver's own status lines and the original's
  "Getting server list" box while it loads.
- On Windows the nickname and the last account are read from and saved to the
  same place the original keeps them, so both programs remember the same
  login.
- On Windows the taskbar button carries the original program's name, as a
  Delphi program's does.
- Alt+Enter switches the game to fullscreen in its own 640 x 480 mode and
  back.
- The game window is titled as the original's (the language file's window name
  and the server's name).
- Training works without an install: the offline tutorial levels inside the
  original exe are compiled in.
- It runs on its own: the files of its original's install that the game reads
  are compiled in, so the exe alone in an empty folder opens on the real
  launcher and plays Training with the original's art.

## Downloads

| Zip | Runs on | Window |
|---|---|---|
| `…-linux.zip` | Linux x86-64 | X11 |
| `…-windows.zip` | Windows, 32-bit | GDI |

Each zip has `Graal21t2` (the client) and the build's README. The test
programs are built and run on every release but no longer shipped.

On Windows the first start may show **"Windows protected your PC"**. That
is SmartScreen meeting an unsigned program it has not seen before, not a
virus warning. Either click **More info**, then **Run anyway** (once), or
unblock the zip before you extract it: right-click it, **Properties**,
tick **Unblock**, **OK**. Then nothing in the folder is asked about again.
See [Windows says "Windows protected your PC"](https://github.com/squirelworks/graal-client-repro#windows-says-windows-protected-your-pc).

## What works

- The test 2 login: gen-3 cipher, zlib framing, token `GNW03081`.
- The server list from `listserver.graal.in` (port 14923; another can be
  named in `listserver.txt`), asked for with the account and password.
- Player props up to 45.
- Levels (`.graal`, `.nw`) and big maps, walking, collision, level links
  and warps, NPCs and GS1, items, combat, signs, weapons, baddies, sound,
  the map and the level editor.

## Running it

```
Graal21t2                                                  # start window
GRAAL_PW=... Graal21t2 --server HOST:PORT --account NAME
Graal21t2 --level some.graal                               # offline
```

Arrow keys walk, Esc leaves the game. `Graal21t2 --help` lists every flag.

## Not yet

This release has only been smoke-tested against the original: start window
and login. The test 2 start window layout and its tabbed options window are
not done.

- [ ] The Options button: the original's options window is not built yet.
- [ ] The launcher's text is drawn with the program's own font, not Windows'
      MS Sans Serif, so some words sit a pixel or two off the original.
- [ ] Sign text shows the `#(13)` line codes instead of breaking the line.
- [ ] At the Training start the status bar shows a bomb after D, and Stefan
      and the player are drawn at once; the original shows only Stefan's name
      at first.
- [ ] The launcher's caption icon is removed for Windows but not yet checked
      on a real PC.
