# Graal NewWorld beta 2 (G2N15041)

A rebuild of the Graal NewWorld beta 2 client in Delphi (Object Pascal). Like the
original it is a windowed program: it opens on a start window with
Training, the server list from the listserver, and login. This is an early,
hit-or-miss first release.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

The program carries what the original's own `Graal-NW.exe` carries: the
start window and server list forms, their art and buttons and the Graal head
icon. It also carries the files of the NewWorld beta 2 install that the game
reads: the tile and sprite sheets, the heads, bodies, swords and shields,
the ganis, the Training and start levels, the maps, the sounds and the
language files. So it runs alone in an empty folder and looks like the
original. Put it at the top of a NewWorld install you own (or keep a
`graal-assets/` folder next to it, or point it at one with `--data DIR`) and
the install's files come first.

## What's new in v0.0.5

- [x] **Minimap only on the map.** The minimap is drawn only on a level of its grid, as the real client does: a server's level off the map (or a house or cave) shows none. Before, it was drawn on every level.
- [x] **F1 Help window.** F1 opens "Help" from the build's own form (TOptions): the "Game windows" group and Close. It is a real dialog on Windows and drawn elsewhere. Edit level opens the editor; the other buttons close it and do nothing yet.
- [x] **Neutral window titles.** The server list window is titled "Server List", not the original's caption, which named the original's host (#191).
- [x] **Pictures by kind.** The picture cache keeps each name once per kind (head, body, sword, shield, hat, weapon), because each kind searches its own folders. A picture first asked for without its kind got the built-in stand-in and kept it, so an install's own picture could stay hidden behind the stand-in (in 1.33, `levels/weapons/wbomb1.gif` beside the D button).

## What's new in v0.0.4

- The A, S and D key letters are drawn the way Graal-NW.exe draws them:
  Windows text at the size it asks for (in a font name Windows does not have,
  so Arial), white, three pixels into each tag. The tags are 60 pixels apart,
  as on the original. Before this the rebuild used its own small block
  letters, and the S looked like a B.
- The NewWorld status bar: the power as "150/150" in the state.png digits,
  next to the bear, and the gralat orb with its count. There are no hearts and
  no bomb or arrow counters, matching the original's screen.
- The names under characters are in Tempus Sans ITC, bold, white over a blue
  shadow, as the original draws them. NewWorld installs carry no tempsitc.ttf,
  so the program falls back to Arial, as Windows does.

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
- Training opens start1.nw in the Bruges and Vangel house, as the original
  does.
- It runs on its own: the files of its original's install that the game reads
  are compiled in, so the exe alone in an empty folder opens on the real
  launcher and plays Training with the original's art.

## Downloads

| Zip | Runs on | Window |
|---|---|---|
| `…-linux.zip` | Linux x86-64 | X11 |
| `…-windows.zip` | Windows, 32-bit | GDI |

Each zip has `GraalNwb2` (the client) and the build's README. The test
programs are built and run on every release but no longer shipped.

On Windows the first start may show **"Windows protected your PC"**. That
is SmartScreen meeting an unsigned program it has not seen before, not a
virus warning. Either click **More info**, then **Run anyway** (once), or
unblock the zip before you extract it: right-click it, **Properties**,
tick **Unblock**, **OK**. Then nothing in the folder is asked about again.
See [Windows says "Windows protected your PC"](https://github.com/squirelworks/graal-client-repro#windows-says-windows-protected-your-pc).

## What works

- The NewWorld login: gen-3 cipher, zlib framing, token `G2N15041`, eight
  colour bytes and the gani by name.
- The `newworld` server list from `listserver.graal.in` (port 14923;
  another can be named in `listserver.txt`).
- The NewWorld tile sheet, tile types, sprites and body from the install.
- Levels (`.graal`, `.nw`) and big maps, walking, collision, level links
  and warps, NPCs and GS1, items, signs, sound, the map and the level
  editor. As in the original there is no built-in sword, bow or baddies.

## Running it

```
GraalNwb2                                                   # start window
GRAAL_PW=... GraalNwb2 --server HOST:PORT --account NAME
GraalNwb2 --level some.nw                                   # offline
```

Arrow keys walk, Esc leaves the game. `GraalNwb2 --help` lists every flag.

## Not yet

This release has only been smoke-tested against the original: start window
and login. The NewWorld clock, the control NPC, string arrays and
terrain heights are not done.

- [ ] The Options button: the original's options window is not built yet.
- [ ] The launcher's text is drawn with the program's own font, not Windows'
      MS Sans Serif, so some words sit a pixel or two off the original.
- [ ] The clock at the bottom left (state.png's clock and the date and
      time) is not drawn yet.
- [ ] The sword picture beside S and its number are not yet the original's.
- [ ] Training opens on the Bruges and Vangel house, but the view is not
      yet placed where the original's is.
- [ ] The launcher's caption icon is removed for Windows but not yet checked
      on a real PC.
