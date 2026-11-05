# Graal 2.0 rev 1 (GNW24011)

A rebuild of the classic Graal 2.0 rev 1 client in Delphi (Object Pascal). Like
the original it is a windowed program: it opens on a start screen with
Training (the offline levels), the server list from the listserver, and
login. This is an early, hit-or-miss first release.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

These zips hold no original Graal code, graphics, sounds or levels. The
program carries small original default graphics and a starter level of its
own, so it runs as it is. Put it at the top of a 2.0 rev 1 install you own (or
keep a `graal-assets/` folder next to it, or point it at one with
`--data DIR`) and the install's tiles, ganis, heads, bodies and levels take
their place.

## What's new in v0.0.3

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
  the program (`src/ResGraal200r1.pas`, made by
  `scripts/res20x/make_res20x.py`): the start and list art, the loading
  screen, `BUTTON1`, all 45 forms, the Training levels and the Graal
  head icon (`src/Graal200r1.ico`, the window and taskbar icon on Windows). No
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

### Not yet

- [ ] Text in the dialogs uses Liberation Sans for the forms' MS Sans
  Serif, so glyphs differ by a pixel here and there.
- [ ] The Options window, the Get an account and homepage GO buttons, and
  the list's right-click menu do nothing yet.
- [ ] The "Getting server list ..." box is drawn inside the list window,
  not as a window of its own.
- [ ] The password is not saved (the real client keeps it in the registry).
- [ ] Names under characters use this project's pixel font, not the real
  client's bold system font.
- [ ] The Windows version block still names this project, not the
  original's company and product strings.

## Downloads

| Zip | Runs on | Window |
|---|---|---|
| `…-linux.zip` | Linux x86-64 | X11 |
| `…-windows.zip` | Windows, 32-bit (as 2.0 rev 1 itself was) | GDI |

Each zip has `Graal200r1` (the client) and the build's README. The test
programs are built and run on every release but no longer shipped.

On Windows the first start may show **"Windows protected your PC"**. That
is SmartScreen meeting an unsigned program it has not seen before, not a
virus warning. Either click **More info**, then **Run anyway** (once), or
unblock the zip before you extract it: right-click it, **Properties**,
tick **Unblock**, **OK**. Then nothing in the folder is asked about again.
See [Windows says "Windows protected your PC"](https://github.com/squirelworks/graal-delphi#windows-says-windows-protected-your-pc).

## What works

- The 2.0 rev 1 login: gen-3 cipher, zlib framing, token `GNW24011`.
- The server list from `listserver.graal.in` (port 14923; another can be
  named in `listserver.txt`), then account and password.
- Levels (`.graal`, `.zelda`) and the big map, drawn from the install's
  tiles and ganis; walking, collision, level links and warps.
- NPCs and the GS1 script engine, items, combat, signs, weapons, baddies,
  sound, the map and the level editor.
- A headless mode for stress runs.

## Running it

```
Graal200r1                                                   # start screen
GRAAL_PW=... Graal200r1 --server HOST:PORT --account NAME
Graal200r1 --level some.graal                                # offline
```

Arrow keys walk, Esc leaves the game. `Graal200r1 --help` lists every flag.

## Not yet

Chat bubbles, the Options page, UDP peer traffic and parts of
GS1 are not done.
