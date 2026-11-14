# Graal 2.31 (GNW28015)

A first rebuild of the classic Graal 2.31 client in Delphi (Object
Pascal). It is a windowed program: it opens on a start screen with
Training (the offline tutorial), the server list from the listserver, and
login. This is version 0.0.1, an early reproduction: it plays, logs in and
walks, but it has not yet been compared action by action with the
original.

**Login token: tested against the real client.** The original was run in the lab and `GNW28015` was seen in its login on the wire (lab capture); this rebuild sends the same token.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

These zips hold no original Graal code, graphics, sounds or levels. The
program carries small default graphics and a starter level of its own, so
it runs as it is. Put it in the folder of a 2.31 install you own, next to
its files, or keep those files in a `graal-assets/` folder beside it.

## What's new in v0.0.5

- [x] **Secure-login pins must be saved.** The shared login code stops before sending the sealed credentials when a new server key cannot be written, closed and read back from the pin file. It reports the save error instead of claiming the key was pinned. An unreadable or non-file pin store also prevents `auto` from falling back to clear-text login, even after a cached refusal.

- [x] **Seihai secure login (optional, off by default).** With `--secure-login auto` (or `required`, or `secure_login.txt` in the settings folder), the account and password go sealed to a Seihai game server or list server (`SEI00001`), after the server's key is checked and pinned. Servers that do not know it get the original login under `auto`. Off, the login is byte for byte the original's. This is not in the original 2.31.

## What's new in v0.0.4.2

- [x] **Minimap only on the map.** The minimap is drawn only on a level of its grid, as the real client does: a server's level off the map (or a house or cave) shows none. Before, it was drawn on every level.
- [x] **Chests from the server are drawn.** A chest that arrives only as `PLO_LEVELCHEST` (4), on a board with no chest tiles, is drawn closed, and one sent as already opened is drawn opened, as the real client does (lab run 2026-11-12). Before, it blocked the player and could be opened but stayed invisible until then.
- [x] **F1 Help window.** F1 opens "Help" from the build's own form (TOptions): the "Game windows" group and Close. It is a real dialog on Windows and drawn elsewhere. Edit level and Debugger are hidden, as 2.31 hides them at run time; the other buttons close it and do nothing yet.
- [x] **Neutral window titles.** The server list window is titled "Server List" and the start window "Graal", not the original's caption, which named the original's host (#191).
- [x] **System weapons stay out of Q.** A weapon whose name starts with `-` (the Reborn server's `-gr_movement`) runs but is not shown in the item list.

- [x] **Graal3D servers.** Without Graal3.exe the note now says Graal3D is needed, without the original's download address, which is gone.
- [x] **Pictures by kind.** The picture cache keeps each name once per kind (head, body, sword, shield, hat, weapon), because each kind searches its own folders. A picture first asked for without its kind got the built-in stand-in and kept it, so an install's own picture could stay hidden behind the stand-in (in 1.33, `levels/weapons/wbomb1.gif` beside the D button).

## What's new in v0.0.4

- Rebuilt from the latest code; the changes for this client are listed here as they land.
- Faithfulness pass: compared side by side with the real 2.31 (under Wine
  and on Windows), and the differences found brought in line with it.
- [x] 2.31's own start window: its background and picture buttons, taken
  out of the real 2.31 program and built into this one, at the places the
  real one shows them. It is its own 577 x 416 window titled
  "Graal", with only a close button, not a screen inside the game
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
- [x] The Options button opens 2.31's "More options" window: its Video,
  Audio, Microphone, Controls and General pages with 2.31's settings,
  read from and saved to `graalconfig.txt` as 2.31 does. "Start in
  fullscreen" is honoured when a game starts.
- [x] Get an account! and Go ask, in 2.31's own "Open URL" box, whether to
  open the page in the browser, and open it when you say yes.
- [x] Typing in the chat line: Tab goes to it, Enter says the line, and
  what you say shows over your head in 2.31's lettering and colours.
- [x] Esc in a game asks "Do you really want to quit Graal?" first.
- [x] Training's look: the wizard, the squirrel and the human2 player
  with its shield, as 2.31 draws them, with the wizard's bobbing green
  arrow and its "Touch to get information" line.
- [x] Training's torches burn: the lamp gani's own script shows the flame
  and its glow, as in 2.31.
- [x] Training's ground is the height-shaped sand and grass 2.31 draws
  from the install's `maps/offlinetutorial.gmap`, with people and things
  standing raised on it.
- [x] Alt+Enter and "Start in fullscreen" switch the screen to the
  "Fullscreen mode" picked in More options (graalconfig.txt's
  fullscreenmode, 1024 x 768 by default), and the game shows more of the
  level there, as the same engine does in 2.22.
- [x] Training does what 2.31's does: it starts `GraalEditor.exe -play`
  from the Graal folder. Without GraalEditor.exe it shows 2.31's
  "GraalEditor.exe has not been found in the Graal folder!" box, and then
  the rebuild plays the tutorial itself (the built-in stand-in for the
  editor's play mode, which 2.31 does not have).
- [x] Editor's not-found message is the same Error box.
- [x] The server list's Show More and Donations buttons, traced from
  Graal_231.exe: hidden in its form, shown when the listserver sends a
  site page (Show More) or an upgrade page (Donations), each opening its
  page through the Open URL box. The Version box shows the start of the
  version, cut at the right.
- [x] On Windows the windows' text is drawn by Windows in the forms' own
  font, MS Sans Serif at 14 px (Font.Height -14 in every form), as 2.31's
  controls draw it; elsewhere the built-in Liberation Sans stands in.
- [x] The start window and server list have no icon in their caption, and
  the account box has the focus when the window opens, its text picked.

## What's new in v0.0.3

- Stress tested before release: a long soak with several players walking
  between levels, others connecting and dropping again and again, and a
  level with 80 scripted NPCs, with no crash, error or memory growth.

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
See [Windows says "Windows protected your PC"](https://github.com/squirelworks/graal-client-repro#windows-says-windows-protected-your-pc).

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

- [ ] Training's heights: side by side with 2.31 the wizard stands about
  25 pixels lower and the torches about 10; 2.31's own height rules are
  not traced yet (the rebuild uses 2.22's). The ground needs the install's
  `maps/offlinetutorial.gmap`; without it Training is drawn flat.
- [ ] Small dark squares every 8 tiles over water (seen in fullscreen).
  They come from the terrain drawing the clients share, not from this
  client.
- [ ] `graal://` and `graal3://` links, NPC movement messages,
  UDP. See the build's README for the full list.

## Checks behind this release

The test suite runs with range and overflow checks and the heap tracer
and ends with no unfreed memory. CI logs two clients into seihai-gserver,
has the second see the first, and walks one through a level link.
