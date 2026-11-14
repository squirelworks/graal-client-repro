# Graal 2.02 rev 1 (`GNW15041`)

The 2.02 rev 1 client, rebuilt. Original: `Graal.exe` 2.02 rev 1, 1,808,896
bytes (MD5 `e06ff79aded885a223b933617d456577`, linked 2001-04-15), Delphi
4/5 with DelphiX. It loads zlib from a `zlib.dll` beside it; the rebuild
has zlib built in and needs no DLL.

This folder starts as a copy of the 2.02 rev 2 rebuild (from the 2.03,
2.04 and `graal-2.05r2-GNW03081` rebuilds), changed where 2.02 rev 1 is
known to differ:

- the login token is `GNW15041` (plain 2.02 sends the same one);
- level files on disk are binary only (GR-V1.00 to 1.03, Z3-V1.03/1.04);
  a `.nw` file is refused (the built-in starter level is exempt);
- the GS1 commands 2.03 and 2.04 added do nothing here: `triggeraction`,
  `move`, `setshape`, `setshape2`, `attachplayertoobj`, `detachplayer`,
  `addtiledef`, `addtiledef2`, `removetiledefs`, `replaceani`;
- it reads the 2.05 rev 2 asset folder after its own, since the 2.0 line
  shipped the same tiles, ganis, heads and bodies.

Everything else is still the 2.05 behaviour, the 0.0.1 starting point. Not
taken out yet: the `vecx`/`vecy` and `onmapx`/`onmapy` functions and the
automatic `actionpushed`/`actionpulled` events (2.03), and 2.04's engine
changes. Rev 1 is the first 2.02 that tells the server the client's
language, which the rebuild does.

## Sources

Everything here is written from the notes in
[graal_analysis](https://github.com/squirelworks/graal_analysis), not from
decompiled code:

| Area | Notes |
|---|---|
| Classes and their split | `client-internals/client-architecture-205.md` |
| Framing, zlib, gen-3 cipher | `protocol/codec-and-framing.md` |
| Login line | `protocol/login-and-walk.md`, `client-internals/version-tokens.md` |
| Message ids | `protocol/packet-ids.md` (2.05 column) |
| Player props | `protocol/player-props.md` (pre-2.1 forms) |
| Levels | `formats/level-binary-client.md`, `formats/glevnw01.txt` |
| Tile sheet | `client-internals/client-assets.md` |
| Frame loop | `client-internals/rendering-observations.md` |
| Walking and collision | `client-internals/decomp-findings-2026-10-25-m/01-walking-rule.md` |
| Ganis | `formats/gani.txt` |
| Sprite prop and poses | `client-internals/feature-specs/11-emotes-ganis.md`, `client-internals/decomp-findings-2026-10-24/sprite-step-table.tsv` |
| Body colours | `client-internals/body-colours-and-attributes.md` |
| Tile types | `formats/arrays-and-signatures.md` |
| Level links and warps | `protocol/packet-layouts.md` (LEVELWARP), `client-internals/feature-specs/06-gmap-overworld.md`, `client-internals/decomp-findings-2026-10-25-j/02-links-and-arrivals.md` |

## Units

| Unit | 2.05 class | What it does |
|---|---|---|
| `src/Protocol202r1.pas` | | ids, token, cipher constants, buffer limits |
| `src/GraalClient.pas` | `TGraalClient`, `TAdventureClient` | out buffer, zlib frames, gen-3 insertion, login, receive split with `PLO_RAWDATA` |
| `src/Adventure.pas` | `TAdventure`, `TServerPlayer` | game state, message handlers, 50 ms tick, drawing |
| `src/Graal202r1.dpr` | | front end: the start screen with no arguments, or the command line (window, scripted keys, frame dump, stress runs) |
| `src/StartScreen202r1.pas` | (`TConnectFrame`, server list) | what 2.05 plugs into the shared start screen (`common/GStartScreen.pas`): its listserver step and its character |
| `src/RunMode.pas` | | stress-run support: clock, stop signals, tick histogram, random walker, JSON |
| `src/Sound202r1.pas` | | the sounds the game plays by itself each tick (gani `PLAYSOUND`), through `common/GSound.pas` |
| `src/Map202r1.pas` | (`TGraalMap`) | the big map on M and the minimap, with every player's head |

## What works

- Login as 2.02 rev 1 sends it: type 0, gen-3 key, `GNW15041`, account,
  password, then `PLI_LANGUAGE`. Every message after the login line carries
  the gen-3 byte. The junk positions match a real 2.05 rev 2 capture (test;
  the cipher is the same).
- Server frames: u16be + zlib, split on LF, `PLO_RAWDATA` blocks across
  frame boundaries.
- Handlers for the login burst: player props (pre-2.1 forms), warp, level
  name, board packet, links, signs, chests, signature, world time, start
  and disconnect messages, set active level.
- Levels from disk: GR-V1.00 to 1.03, Z3-V1.03/1.04 (no GLEVNW01 in 2.02 rev 1). All 13 tutorial
  levels embedded in the original exe decode to the published tiles, and
  their boards re-encode byte for byte with the 2.05 writer rules (test, with
  the levels supplied locally).
- Drawing: the board from `pics1` with the 2.05 sheet layout, centred on the
  player, into a 640x480 frame. The player is drawn from the install's ganis
  (`idle`, `walk`) with head, body, sword and shield images, and the body is
  recoloured from the five colour props.
- Actions, from the 2.05 cut, lift and chest code: S swings the sword and
  cuts a bush or tall grass at the tip; A lifts a bush, sign or pot (a glove
  adds stones), carries it overhead and throws it (S or A); A on a chest
  opens it and gives its item. Online the board change goes out as
  `PLI_BOARDMODIFY` and the open as `PLI_OPENCHEST`. Server board changes
  (`PLO_BOARDMODIFY`) are applied. The throw's flight is not read from 2.05
  yet: it flies four tiles and goes.
- Items on the floor (`PLO_ITEMADD` / `PLO_ITEMDEL`), drawn with their
  shadow, bounce and last-moments blink; walked over after the first four
  ticks they are taken (`PLI_ITEMTAKE` online, given at once offline), and
  after 8.2 s they go (`PLI_ITEMDEL` online). Offline nothing drops, as in
  2.05 (tests).
- Combat, from the 2.05 hurt and bomb code: a hit takes half hearts (after
  clamping to the maximum), knocks the player back a tile a tick for five
  ticks and gives 40 ticks of hurt mode; no hearts left is death, and a
  direction key respawns at the level's entry point with hearts by AP.
  Other players' swings are judged on this side (on their swing sprites,
  0 to 4 tiles ahead, once a second); `PLO_HURTPLAYER` is taken from known
  players within 10 tiles. D lays a bomb with a 60-tick fuse; its cross blast
  (reach 2, 11 ticks) cuts bushes, breaks pots and stones, and hurts.
  Bombs and explosions go out and come in (`PLI_BOMBADD`, `PLI_EXPLOSION`,
  `PLO_BOMBADD`, `PLO_BOMBDEL`, `PLO_EXPLOSION`) (tests). Where 2.05 puts a
  new bomb was not read: a tile and a half ahead.
- Signs, from the 2.05 sign panel: walking up into a sign (or opening a
  chest that names one) shows it on the scroll from `letters.png`, three
  lines a page, with the `#` button pictures. Up turns back a page, any
  other game key turns on, and on a page that is not full ends reading;
  nothing walks or acts while reading (tests). The glyph advances other
  than I, space and the common letters, and the button pictures for `#h`,
  `#x`, `#y`, `#z`, `#4` and `#.`, are guesses; `#i` images are skipped.
- Weapons, from the 2.05 weapon list: one list of built-in weapons (bow,
  bomb, superbomb, fireball, fireblast, nukeshot, joltbomb) and server NPC
  weapons, the selected one drawn beside the D button. Offline the player
  starts with the bomb, and a bow chest sits by the start. D uses the selected
  weapon: bombs, or a shot that flies a tile a tick (`PLI_ARROWADD`).
  Others' shots (`PLO_ARROWADD`) take half a heart or a heart, and a shield
  facing them stops arrows and fireballs. Q opens the item list: arrow keys
  pick a weapon, and any other key closes it. `PLO_DEFAULTWEAPON`,
  `PLO_NPCWEAPONADD` (the name only) and `PLO_NPCWEAPONDEL` are handled
  (tests). Not read from 2.05: where a shot starts, whether arrows go
  through walls (here they stop), and the item list's look beyond its
  layout.
- The status display, laid out as 2.05 draws it from `state.png`: the A/S/D
  buttons, the item icons with rupee, bomb and arrow counts, big hearts up
  to four containers and small hearts in rows past that, and the alignment
  bar. A new account starts at 3 hearts, 10 bombs and 5 arrows. The
  built-in `state.png` is new art in the same layout (tests). Not drawn yet:
  the glove and sword icons, the selected weapon and the magic bar.
- A window (X11 on Linux, GDI on Windows) with keyboard input: arrows or
  IJKL walk, Esc quits. `--keys` drives the same input from a script, so
  headless runs can walk too.
- Walking with the 2.05 rule: half-tile steps, six probes per facing, the
  0.1 corner nudge, keys taken in the order up, left, down, right. Blocking
  comes from `arrays.dat` tile types and level chests (tests).
- Props out: the session-start set {0, 11, 13, 18, 31, 33}, then position
  and sprite whenever they change, at most every 100 ms. The sprite prop is
  direction + 4 x the 2.05 sprite number of the current animation step, so
  walk frames go out as they do from the original.
- Other players (`PLO_OTHERPLPROPS`): added on first sight, drawn with
  their head, body colours and pose from their sprite prop, and removed on
  `PCONNECTED` or a level leave. Each prop stream stops at the first id
  2.05 would not accept in it, as the original does (tests).
- Level links: the player's own walk is tested against the level's links,
  at one point: the body's centre (x + 1.5, y + 2) pushed 1.25 tiles ahead
  in the walking direction. That point was measured on the real 2.05 under
  Wine (1 to 1.5 tiles ahead, on the centre line across the walk, so a 1x1
  link off that line is walked past); the tests repeat those runs.
  Online, a link sends `PLI_LEVELWARP` (arrival x, y and the level name), and
  the client completes the warp itself when the new level arrives, since
  the server sends no `PLAYERWARP` for it. Offline, the level is loaded from
  next to the current one or from the install. Arrivals may be decimals, and
  `playerx` / `playery` or a negative value keep that coordinate (tests).
- Loopback: two clients log into seihai-gserver, load the board and walk;
  the second must see the first. Then one walks through a level link
  (`scripts/loopback.sh`, run in CI).

## Sound and maps

- Effects are `.wav` files from `sounds/` (beside the program or under
  `--data` first, then `graal-assets/2.02r1/`, `graal-assets/2.05r2/`, then `graal-assets/common/`);
  a missing one is silent. They play only with a window, and `--nosound`
  turns them off. Windows plays through waveOut, Linux through ALSA loaded
  at run time (no ALSA, no sound, no error), macOS not at all yet.
- As in 2.05: at most 8 effects at once, each of the 15 effects 2.05 knows
  by name at most once a tick, a `+` in front loops, pan and volume from
  the distance to the player (the formula from the 2.05 binary is in
  `common/GSound.pas`). Played so far: gani `PLAYSOUND` (sword, lift,
  steps, and `lift.wav` on hurt and death), `extra.wav` on taking an item,
  `chest.wav` on opening a chest, `crush.wav` when a thrown object lands,
  `put.wav` on laying a bomb, `bomb.wav` for a blast, `dead.wav` on dying.
- Music (`.mid`) goes to MCI on Windows and loops, as 2.05's MCI path does;
  it is silent elsewhere, and nothing starts music until the script engine
  is in.
- M opens the big map (`bigmap.txt` + `map.png`, 56 px a level): centred
  on the player's head and kept inside the map, the arrows scroll it 8 px a
  tick, M closes it. The minimap (`minimap.txt` + `map2.png`) sits in the
  bottom-left corner with the status display (showstats bit 0x100).
  Offline on the tutorial both switch to `tutorialmap.txt`.

## Where to put your Graal files

The zip has no Graal files in it. Put yours in the same folder as
`Graal202r1` (on Windows `Graal202r1.exe`), in either of these ways:

- Unzip `graal-assets.zip` into that folder, so the folder holds
  `Graal202r1.exe` and `graal-assets/` side by side.
- Or copy the contents of a Graal 2.05 install into that folder:
  `levels/`, `sounds/`, `pics1.png`, `body.png`, `sprites.png` and the rest,
  laid out as the install has them.

```
Graal 2.05/
  Graal202r1.exe
  graal-assets/        (from graal-assets.zip)
    common/
    2.05r2/
```

The original `Graal.exe` is not needed. Only that folder is read, never
the folder above it. `--data DIR` points at another folder instead.

## Playing online

Press Start, type your account and password, then press Enter (or
Refresh) to get the server list from listserver.graal.in:14923. Pick a
server and press Connect. A `listserver.txt` next to the program (host on
the first line, port on the second) names another listserver.

## Start screen and built-in assets

Run `Graal202r1` with no arguments and it opens a window, as 2.05 did, with
the start screen of its connect dialog: a nick name, the character, and the
buttons Training, Options and Start. Training plays the offline levels;
Start takes an account and password and asks the listserver for the
server list with them (id 0 `newmain` and id 1 account and password in one
plain zlib frame, the classic login the public legacy port answers; the
reply has the 2.05 layout), then logs into the server picked. Esc in the game, or a lost link, goes back to the start
screen. Options is not built yet. On Windows it is a windowed program with
no console; given flags, it attaches to the console it was started from.

The listserver is read from `listserver.txt` next to the program (first
line host, second line port), else listserver.graal.in:14923 (the
legacy-clients port; 14922 serves supported clients). The real 2.05 hides
its listserver host in the exe; that is not used.

The program carries a small set of its own, original assets
(`common/builtin/`, made by `scripts/builtin/make_builtin.py` and compiled
in as `common/GBuiltin.pas`): a tile sheet, a body, a head, the shadow,
`idle` and `walk` ganis, `arrays.dat`, and two linked offline levels. They
are drawn new for this project and are not the 2.05 graphics. Anything the
program finds on disk wins over them: put a 2.05 install (or the assets
zip) next to the program, or point `--data` at one, and its `pics1`,
ganis, heads, bodies and levels are used in the game instead.
Training starts at `levels/tutorial_b-4.graal` when that file is there,
else at the built-in `start.nw`.

The start window and server list are this build's original ones. Every
RCDATA resource of the original `Graal.exe` (the start and list art, the
loading screen, `BUTTON1`, all the Delphi forms, the Training levels) is
compiled into the program as `src/ResGraal202r1.pas`, with the bytes the 2.0x
exes share kept once in `common/GRes20x.pas`; the Graal head icon is
`src/Graal202r1.ico`. `scripts/res20x/make_res20x.py` makes them from the
original installs. `common/GRealStart20.pas` lays the two windows out from
the forms (`TConnectFrame`, `TServerListFrame`, `TShortMessage`), read
with `common/GDfm.pas`. The project's own start screen
(`common/GStartScreen.pas`) is used only if those resources do not load.

## Stress runs (phase 4)

The same client runs headless for the Seihai stress runs, one process per
client:

```
GRAAL_PW=... Graal202r1 --server 127.0.0.1:14802 --account bot17 --headless \
  --seconds 600 --walk random --walk-ms 100 --seed 17 --link-every 5 \
  --stats-every 10
```

- `--headless` skips drawing; the 50 ms frame gate sleeps, so an idle
  client costs almost nothing. 50 clients walking at random and taking a
  link every 3 s used 7.7% of one core in total, about 4.6 MB RSS each,
  tick p99 under 0.7 ms.
- `--seconds N`, or `--frames 0` to run until stopped. SIGTERM / SIGINT
  (Ctrl+Break / Ctrl+C on Windows) flush, close the link and end cleanly.
- `--walk random|idle|script`, `--walk-ms`, `--seed`, `--link-every N`
  (head for the nearest link every N seconds). The walk has its own random
  generator, so the seed does not change the gen-3 key.
- `--nodelay` sets `TCP_NODELAY`. It is off by default, which is WinSock's
  default and so presumably the original's (not traced).
- Logs go to stderr. Stdout gets one JSON line at the end
  (`"kind":"summary"`), and with `--stats-every N` a `"kind":"stats"` line
  every N seconds with the same fields: version, token, account, end
  (`clean`, `nologin`, `dropped`, `error`), error, login_ms (connect to the
  first board), run_s, ticks, frames and messages in and out, bytes in and
  out, warps sent and completed, warp_ms p50 and max (link request to the
  new board, so a multiple of the 50 ms tick), tick_ms p50, p99 and max,
  rss_peak_kib (Linux only; null elsewhere), nodelay.
- Exit codes: 0 clean, 1 error, 2 never logged in, 3 dropped after login,
  64 bad command line.

Hardening checks, all in CI:

- The test program is built with range and overflow checks and the heap
  tracer; `scripts/test.sh` fails on any unfreed memory.
- A fuzz test sends 20000 random and mangled messages and 3000 random frames
  (valid zlib around random messages, `RAWDATA` blocks, split deliveries,
  garbage) through the receive path. With `GRAAL202r1_DATA` set to an install,
  the drawing of the fuzzed players is covered too.
- The receive path is linear in the input (frames and messages are read by
  position) and has limits of its own (an inflated frame over 16 MB or an
  unfinished message over 4 MB drops the link); 2.05's own limits are not
  known.
- The loopback check needs a clean JSON summary from each client.

## Seihai secure login (not in the original)

Off by default, so the login is byte for byte the original's. With
`--secure-login auto` or `required` (or one word in `secure_login.txt` in
the shared settings folder), the account and the password go sealed to a
Seihai game server (version token `SEI00001`, graal-client-repro #148).
C1 carries the type and key bytes of the classic login and this build's token, and
C2 stands in for the login line. What the build sends with its login line follows C2 in the same frame, gen-3 coded from the first step. Same code and settings as 2.31: see the 2.31 README,
"Seihai secure login". CI logs in once more with `--secure-login required`
(`scripts/loopback.sh`).

## Not yet

- [ ] Sound: music outside Windows, Winamp, `lift2.wav` for female players,
  sounds for actions not built yet (arrows, swimming, signs, horses), the `setmusicvolume` / `play` script commands, asking the server
  for a missing sound file.
- [ ] Maps: the text 2.05 writes at the top left of the big map, names under
  the mouse, the small head icons, chat marks on the minimap, `setmap` /
  `setminimap` from scripts and maps from the server list entry.
- [ ] The link test point while walking diagonally, standing on a link, and at
  the level edge was not measured; diagonally the two offsets add.
- [ ] `PLI_LEVELWARPMOD` for cached levels; every link sends `PLI_LEVELWARP`.
- [ ] UDP peer traffic.
- [ ] Other players' poses beyond idle and walk, chat bubbles and names.
- [ ] Most of the 59 server ids 2.05 handles. NPCs, baddies, items, weapons
  and the rest of the game.
- [ ] The GS1 script engine (161 commands), the built-in editors.
- [ ] The listserver host hidden in the 2.05 exe (DES); `listserver.txt` names it instead.
- [ ] The window size (640x480 is assumed, not read from the binary). The
  board edge is treated as open.
- [ ] Several clients in one process (one per process for now).
- [ ] The Options page, the language and character pickers of the start screen.
