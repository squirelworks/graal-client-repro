# Graal 2.3 (GNW14015)

A first rebuild of the classic Graal 2.3 client in Delphi (Object
Pascal). It is a windowed program: it opens on a start screen with
Training, the server list from the listserver, and login. This is version
0.0.1, an early reproduction: it plays, logs in and walks, but it has not
yet been compared with the original, and some of what it sends is a
stand-in until the original program has been studied.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

These zips hold no original Graal code, graphics, sounds or levels. The
program carries small default graphics and a starter level of its own, so
it runs as it is. Put it in the folder of a 2.3 install you own, next to
its files, or keep those files in a `graal-assets/` folder beside it.

## What's new in v0.0.4

- Faithfulness pass: 2.3 follows 2.31 (no 2.3 program survives), which was
  compared side by side with the real 2.31 and brought in line with it.
- [x] No 2.3 program survives, so 2.3 is now modelled on 2.31, the nearest
  real client (a few weeks newer). Everything below is 2.31's, taken out of
  the real 2.31 program and built into this one.
- [x] The start window as 2.31 has it: its own 577 x 416 window titled
  "GraalOnline", with only a close button, its background and picture
  buttons, and Training, Editor, Options, Get an account! and Start.
  Editor starts GraalEditor.exe from the Graal folder.
- [x] The server list as 2.31 has it: the tabs Graal Gold, Graal 3D,
  Classic and Hosted, and Connect.
- [x] Account and password start empty; the nickname and the last account
  are remembered between runs on Windows.
- [x] The Training levels are built in, so Training works without an
  install.
- [x] The game window: 640 x 480, titled "G r a a l" with spaces around it
  as 2.31 does, the white chat line along the bottom, and Alt+Enter for
  fullscreen and back.
- [x] The Graal head icon in the title bar and the taskbar.
- [x] Options opens 2.31's "More options" window (Video, Audio,
  Microphone, Controls, General), read from and saved to
  `graalconfig.txt`; "Start in fullscreen" is honoured.
- [x] Get an account! and Go ask in 2.31's "Open URL" box before opening
  the page in the browser.
- [x] Typing in the chat line: Tab goes to it, Enter says the line, and it
  shows over your head; Esc in a game asks before quitting.
- [x] Training as 2.31 draws it: the height-shaped sand and grass (from
  the install's `maps/offlinetutorial.gmap`), the burning torches, the
  wizard with its arrow and "Touch to get information", the squirrel and
  the human2 player.
- [x] Alt+Enter switches to a real 640 x 480 fullscreen mode and back.
- [x] Training does what 2.31's does: it starts `GraalEditor.exe -play`
  from the Graal folder; without it, the "GraalEditor.exe has not been
  found in the Graal folder!" box, and then the rebuild plays the tutorial
  itself (its stand-in for the editor's play mode). Editor's not-found
  message is the same box.
- [x] The server list's Show More and Donations, traced from
  Graal_231.exe: shown when the listserver sends a site page (Show More) or
  an upgrade page (Donations), each opening its page through the Open URL
  box. The Version box shows the start of the version.
- [x] On Windows the windows' text is drawn by Windows in the forms' own
  font, MS Sans Serif at 14 px; elsewhere the built-in Liberation Sans
  stands in.
- [x] The start window and server list have no icon in their caption; the
  account box has the focus when the window opens, its text picked.

## What's new in v0.0.3

- Stress tested before release: a long soak with several players walking
  between levels, others connecting and dropping again and again, and a
  level with 80 scripted NPCs, with no crash, error or memory growth.

## Downloads

| Zip | Runs on | Window |
|---|---|---|
| `…-linux.zip` | Linux x86-64 | X11 |
| `…-windows.zip` | Windows, 32-bit | GDI |

Each zip has `Graal230` (the client) and the build's README. The test
programs are built and run on every release but no longer shipped.

On Windows the first start may show **"Windows protected your PC"**. That
is SmartScreen meeting an unsigned program it has not seen before, not a
virus warning. Either click **More info**, then **Run anyway** (once), or
unblock the zip before you extract it: right-click it, **Properties**,
tick **Unblock**, **OK**. Then nothing in the folder is asked about again.
See [Windows says "Windows protected your PC"](https://github.com/squirelworks/graal-delphi#windows-says-windows-protected-your-pc).

## What works

- The start screen: nick name, Training, Start. Start fetches the server
  list (the install's `arrays2.dat`, or `listserver.txt` next to the
  program, else `listserver.graal.in:14922`), then account, password and
  Connect.
- Login with the `GNW14015` version token.
- Full-precision positions of players and NPCs.
- The board, the player and other players, walking and collision, level
  links, gmaps and walking over their edges.
- S sword, A lift / throw / open, D weapon, Q item list, M map; items,
  bombs, hearts, death and respawn; signs; level NPCs and their scripts;
  baddies; sound effects.
- A headless mode for stress runs.

## Not yet

- [ ] Anything 2.3 did differently from 2.31: with no 2.3 program, none of
  it can be checked. The version profile says 2.3 lacks 2.31's fixes
  (gmap NPC border crossing, number to text, saving the key setup).
- [ ] The client's own tamper check bytes (a stand-in is sent).
- [ ] Training's heights: some things stand a little lower than in 2.31
  (the wizard about 25 pixels); without the install's gmap Training is
  drawn flat.
- [ ] Fullscreen uses 640 x 480, not the "Fullscreen mode" in More options.
- [ ] The F1 window, NPC movement messages, UDP. See the build's README.

## Checks behind this release

The test suite runs with range and overflow checks and the heap tracer
and ends with no unfreed memory. CI logs two clients into seihai-gserver,
has the second see the first, and walks one through a level link.
