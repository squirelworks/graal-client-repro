# Graal 2.31 (GNW28015)

A first rebuild of the classic Graal 2.31 client in Delphi (Object
Pascal). It is a windowed program: it opens on a start screen with
Training (the offline tutorial), the server list from the listserver, and
login. This is version 0.0.1, an early reproduction: it plays, logs in and
walks, but it has not yet been compared action by action with the
original.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

These zips hold no original Graal code, graphics, sounds or levels. The
program carries small default graphics and a starter level of its own, so
it runs as it is. Put it in the folder of a 2.31 install you own, next to
its files, or keep those files in a `graal-assets/` folder beside it.

## What's new in v0.0.3

- Faithfulness pass: compared side by side with the original program it was
  rebuilt from, and the differences found brought in line with it.
- Stress tested before release: a long soak with several players walking
  between levels, others connecting and dropping again and again, and a
  level with 80 scripted NPCs, with no crash, error or memory growth.
- [x] 2.31's own start window: its background and picture buttons, taken
  out of the real 2.31 program and built into this one, at the places the
  real one shows them. It is its own 577 x 416 window titled
  "GraalOnline", with only a close button, not a screen inside the game
  window.
- [x] Its five buttons as 2.31 has them: Training (the wide one, at the
  top), Editor, Options, Get an account! and Start. Editor starts
  GraalEditor.exe from the Graal folder, or says it is not there, as 2.31
  does.
- [x] The server list as 2.31 shows it: the tabs Graal Gold, Graal 3D,
  Classic and Hosted, Connect, and the server box under the list. A
  Graal 3D server opens Graal3.exe when the folder has it, else gives
  2.31's "You need to download Graal3D" message.
- [x] Account and password start empty, as in 2.31; the nickname and the
  last account are remembered between runs on Windows.
- [x] The Training levels 2.31 carries in its program are built in, so
  Training opens 2.31's tutorial even without an install.
- [x] The game window is 640 x 480, titled "G r a a l" with spaces around
  it the way 2.31 does it, or "Graal: <server>" online.
- [x] The white chat line along the bottom of the game window; the play
  area is the 456 pixels above it.
- [x] Alt+Enter switches the game to fullscreen and back, as in 2.31.
- [x] 2.31's own icon in the title bar and the taskbar.

## Downloads

| Zip | Runs on | Window |
|---|---|---|
| `…-linux.zip` | Linux x86-64 | X11 |
| `…-windows.zip` | Windows, 32-bit | GDI |

Each zip has `Graal231` (the client) and the build's README. The test
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
- Login as 2.31 sends it: `GNW28015` and its tamper check, which it sends
  again about every 3.2 seconds while playing.
- Tells the server each time it enters a level.
- Reads full-precision positions of players and NPCs.
- The board, the player and other players, walking and collision, level
  links, gmaps and walking over their edges.
- S sword, A lift / throw / open, D weapon, Q item list, M map; items,
  bombs, hearts, death and respawn; signs; level NPCs and their scripts;
  baddies; sound effects.
- A headless mode for stress runs.

## Not yet

- [ ] The Options window (2.31's TMoreOptions) behind the Options button.
- [ ] Get an account! and the Go button open nothing yet.
- [ ] Training's look: 2.31 draws the tutorial with the picso tiles, the
  torch lights, the wizard and the "Touch to get information" text; the
  rebuild still shows the level with the install's normal tiles.
- [ ] Typing in the chat line.
- [ ] Dialog text is drawn in Liberation Sans, not Windows' MS Sans Serif.
- [ ] `graal://` and `graal3://` links, the F1 window, NPC movement
  messages, UDP. See the build's README for the full list.

## Checks behind this release

The test suite runs with range and overflow checks and the heap tracer
and ends with no unfreed memory. CI logs two clients into seihai-gserver,
has the second see the first, and walks one through a level link.
