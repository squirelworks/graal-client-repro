# Graal 2.0 (GNW24011)

A rebuild of the classic Graal 2.0 client in Delphi (Object Pascal). Like
the original it is a windowed program: it opens on a start screen with
Training (the offline levels), the server list from the listserver, and
login. This is an early, hit-or-miss first release.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

These zips hold no original Graal code, graphics, sounds or levels. The
program carries small original default graphics and a starter level of its
own, so it runs as it is. Put it at the top of a 2.0 install you own (or
keep a `graal-assets/` folder next to it, or point it at one with
`--data DIR`) and the install's tiles, ganis, heads, bodies and levels take
their place.

## What's new in v0.0.4

- Rebuilt from the latest code; the changes for this client are listed here as they land.
- [x] The launcher is this build's own: the start window is the real
  `TConnectFrame`, a 476 x 330 "Graal 2001" dialog with only the close
  button, over the real start art (`SCREENIMG1`), with its labels, language
  box and nickname placed from the form, and the Training, Options and
  Start buttons drawn from `BUTTON1` where the real one paints them.
- [x] Start opens the server list as its own 577 x 416 window
  ("Graalonline.com Server List", `SCREENIMG2`), laid out from this exe's
  `TServerListFrame`: the 2.0 to 2.01 rev 1 server list form, with its RichEdit description box and its two server icons.
  "Getting server list ..." shows in the `TShortMessage` box while the
  listserver answers. The account and password are typed on the list, as
  in the real client, and the list is asked for with id 0 alone first.
- [x] Every resource of this build's original `Graal.exe` is compiled into
  the program (`src/ResGraal200.pas`, made by
  `scripts/res20x/make_res20x.py`): the start and list art, the loading
  screen, `BUTTON1`, all 45 forms, the Training levels and the Graal
  head icon (`src/Graal200.ico`, the window and taskbar icon on Windows). No
  original program or install is needed for the launcher or Training.
- [x] Training plays the tutorial levels from this build's own exe
  (`TUTORIALB4` is 10122 bytes here, the version before 2.0 rev 3 changed it),
  written out once to a folder of its own under the system's temp folder.
- [x] The game opens in its own 640 x 480 window titled "Graal", as the
  real `TAdventure`, and Esc goes back to the start window.
- [x] The nickname and last account are read from and saved to
  `HKCU\Software\Graal\Client` (`nickname`, `accountname`) on Windows,
  as the real client keeps them.
- [x] A language file next to the program (`language<Name>.txt`) renames
  the start window's controls by name (`StartScreen-<Name>=`), as the real
  client does.
- [x] The side-by-side fixes made on 2.05 rev 2 under Wine: the chat line
  along the bottom (456-pixel play area above it), throwing with its arc,
  shadow and pieces, hiding under a carried bush or stone, hearts over a
  hit character, the next level drawn past the board's edge, pictures found
  in any folder under `levels/`, and palette pictures keyed on colour 0.

- [x] The windows behave as the real Delphi program's do on Windows: the
  taskbar entry is the program's hidden "Graal" application window, the
  start window and server list have no title-bar icon, and the game
  window can be resized, minimised and maximised.
- [x] Alt+Enter in the game switches to full screen at `graalconfig.txt`'s
  `fullscreenmode` (640x480 when not set) and back.
- [x] The language box drops down its list (8 rows and a scroll bar, the
  mouse picks), and picking a language reads its file at once. Names such
  as `languageEspa#U00f1ol.txt` show as Español; the dialog font now has
  every Windows-1252 character.
- [x] The Training, Options and Start captions are 12 pt bold as on the
  real one, the accelerator letter only red where Windows shows keyboard
  cues, and selections use Windows' own highlight colour.
- [x] The server list is titled "... (loading...)" until the servers are
  in, as the real one is.
- [x] Pictures are found by their exact names anywhere in the install
  (`head0.gif`, `sword1.gif`, `wbomb1.gif`, `body.png`), as the real exe
  lists its whole folder tree and opens them (traced under Wine): a
  `.png` is not taken for a `.gif`, and with an install present a
  missing picture stays missing instead of the built-in art filling in.
- [x] The status display's A, S and D (and the small Q) are drawn as the
  real one draws them, traced under Wine: GDI "Helvetica" bold, cells 26
  and 10 high, at the traced points, white over black. They were this
  project's blocky pixel font, whose S read as a B.
- [x] Names under characters and the sword and glove powers use
  `graalconfig.txt`'s font (Tempus Sans ITC, a cell 24 high, bold), read
  from the install or Windows' Fonts folder, as the real one asks GDI for
  it; the pixel font only when the font is nowhere.
### Not yet

- [ ] Text in the dialogs uses Liberation Sans for the forms' MS Sans
  Serif, so glyphs differ by a pixel here and there.
- [ ] The Options window, the Get an account and homepage GO buttons, and
  the list's right-click menu do nothing yet.
- [ ] Full screen stretches the 640 x 480 picture; whether 2.0x showed
  more of the level at 800 x 600 and 1024 x 768 is not checked yet.
- [ ] The "Getting server list ..." box is drawn inside the list window,
  not as a window of its own.
- [ ] The password is not saved (the real client keeps it in the registry).
- [ ] The Windows version block still names this project, not the
  original's company and product strings.

## What's new in v0.0.3

- The Windows program carries its original's own icon (the Graal head, taken from
  the original exe), so Explorer shows it as the original did.
- Stress tested before release: a long soak with several players walking
  between levels, others connecting and dropping again and again, and a
  level with 80 scripted NPCs, with no crash, error or memory growth.

## Downloads

| Zip | Runs on | Window |
|---|---|---|
| `…-linux.zip` | Linux x86-64 | X11 |
| `…-windows.zip` | Windows, 32-bit (as 2.0 itself was) | GDI |

Each zip has `Graal200` (the client) and the build's README. The test
programs are built and run on every release but no longer shipped.

On Windows the first start may show **"Windows protected your PC"**. That
is SmartScreen meeting an unsigned program it has not seen before, not a
virus warning. Either click **More info**, then **Run anyway** (once), or
unblock the zip before you extract it: right-click it, **Properties**,
tick **Unblock**, **OK**. Then nothing in the folder is asked about again.
See [Windows says "Windows protected your PC"](https://github.com/squirelworks/graal-client-repro#windows-says-windows-protected-your-pc).

## What works

- The 2.0 login: gen-3 cipher, zlib framing, token `GNW24011`.
- The server list from `listserver.graal.in` (port 14923; another can be
  named in `listserver.txt`), then account and password.
- Levels (`.graal`, `.zelda`) and the big map, drawn from the install's
  tiles and ganis; walking, collision, level links and warps.
- NPCs and the GS1 script engine, items, combat, signs, weapons, baddies,
  sound, the map and the level editor.
- A headless mode for stress runs.

## Running it

```
Graal200                                                   # start screen
GRAAL_PW=... Graal200 --server HOST:PORT --account NAME
Graal200 --level some.graal                                # offline
```

Arrow keys walk, Esc leaves the game. `Graal200 --help` lists every flag.

## Not yet

Chat bubbles, the Options page, UDP peer traffic and parts of
GS1 are not done.
