# Graal NewMain 26 (GNW08011)

A rebuild of the Graal NewMain 26 client in Delphi (Object Pascal). Like the
original it is a windowed program: it opens on a start window with
Training, the server list from the listserver, and login. This is an early,
hit-or-miss first release.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

The program carries what the original's own `Graal-NewMain26.exe` carries:
the start window and server list forms, their art and buttons, the character
list and the Graal head icon. It also carries the files of the NewMain 26
install that the game reads: the tile and sprite sheets, the heads, bodies,
swords and shields, the ganis, the Training and start levels, the maps, the
sounds and the language files. So it runs alone in an empty folder and looks
like the original. Put it at the top of a NewMain install you own (or keep a
`graal-assets/` folder next to it, or point it at one with `--data DIR`) and
the install's files come first.

## What's new in v0.0.5

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
- The server list asks for the account and password itself, as this version's
  original does.
- The character box lists the characters from headsconfig.txt (the install's,
  else the copy the program carries), opens on the one graalconfig.txt last
  picked, and the pick dresses your player with its head and colours and is
  saved back for next time.
- Training opens the offline tutorial (levels/tutorial/), as the original
  does.
- It runs on its own: the files of its original's install that the game reads
  are compiled in, so the exe alone in an empty folder opens on the real
  launcher and plays Training with the original's art.

## Downloads

| Zip | Runs on | Window |
|---|---|---|
| `…-linux.zip` | Linux x86-64 | X11 |
| `…-windows.zip` | Windows, 32-bit | GDI |

Each zip has `GraalNm26` (the client) and the build's README. The test
programs are built and run on every release but no longer shipped.

On Windows the first start may show **"Windows protected your PC"**. That
is SmartScreen meeting an unsigned program it has not seen before, not a
virus warning. Either click **More info**, then **Run anyway** (once), or
unblock the zip before you extract it: right-click it, **Properties**,
tick **Unblock**, **OK**. Then nothing in the folder is asked about again.
See [Windows says "Windows protected your PC"](https://github.com/squirelworks/graal-client-repro#windows-says-windows-protected-your-pc).

## What works

- The NewMain login: gen-3 cipher, zlib framing, token `GNW08011`, no
  LANGUAGE packet, player props up to 36.
- The `newmain` server list from `listserver.graal.in` (port 14923;
  another can be named in `listserver.txt`).
- Levels (`.graal`, `.nw`) and big maps, walking, collision, level links
  and warps, NPCs and GS1, items, signs, the sword, bow, bombs and baddies,
  sound, the map and the level editor.

## Running it

```
GraalNm26                                                   # start window
GRAAL_PW=... GraalNm26 --server HOST:PORT --account NAME
GraalNm26 --level some.nw                                   # offline
```

Arrow keys walk, Esc leaves the game. `GraalNm26 --help` lists every flag.

## Not yet

This release has only been smoke-tested against the original: start window
and login. The file requests at login, NewMain's first gani system and the
1.42 level features are not done.

- [ ] The Options button: the original's options window is not built yet.
- [ ] The launcher's text is drawn with the program's own font, not Windows'
      MS Sans Serif, so some words sit a pixel or two off the original.
- [ ] Sign text shows the `#(13)` line codes instead of breaking the line.
- [ ] The launcher's caption icon is removed for Windows but not yet checked
      on a real PC.
