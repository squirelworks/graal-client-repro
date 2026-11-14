# common/cpp/quattro: the Quattro program

The late-5 and 6.x clients are not Torque. From 5.24 on, every Windows,
Linux and Mac build is one native C++ program whose source paths say
`quattro_lib` and whose play name is `Quattro_Play`. This directory
rebuilds that program, in C++, for the folders that run it. It is the
"separate own-engine track" of
[#109](https://github.com/squirelworks/graal-client-repro/issues/109), and
Track D of the v3-to-v6 plan: the shared GS2 script machine is Track B, in
`common/cpp/gs2/`, and this program hosts it.

No original code is in here. Behaviour comes from the Graal_analysis notes
named in each file's header, which tag their evidence.

## What the original program is

Read from Graal_analysis `client-internals/engine-600r2.md`,
`client-internals/unpacked-6037.md`, `client-internals/issho-cut.md` and
`protocol/v6x-clients.md`:

- **Drawing.** OpenGL presents the frame (Direct3D 9 is only a capability
  check on Windows). The world is drawn in named passes (`Game_Draw`,
  `Game_Draw_GetDrawObjects`, `Game_Draw_Player`, `Game_Draw_Texts`,
  `Draw_Tiles`, `Draw_ShowImg`, `Draw_Particles`), then the GUI
  (`RenderGUI`, one `Draw_*` routine per control type).
- **GUI.** GS2 controls with Torque's names (`GuiWindowCtrl`,
  `GuiScrollCtrl`, `GuiMLTextCtrl`, ...) and Graal's own
  (`GuiGraalCtrl` playfield, `GuiShowImgCtrl`, PM, start menu). Every
  shell dialog is a script: `StartScript_Profiles`,
  `StartScript_GraalGui`, `StartScript_MessageBoxDialog`,
  `StartScript_SetupDialog`, `StartScript_SelectFileDialog`, the connect
  message. The server list and account screens come from the Login
  server's scripts.
- **Script.** The GS2 machine on `TGraalVar` values, the `TServer*` world
  objects, classes and joins, and the `GRESCR01` script cache.
- **Network.** `TSocket` with the gen-5 codec. No Torque connection, no UDP.
- **Files.** Levels `GR-V1.03` to `GR-V1.05` (6.00 also reads 1.00 to
  1.02), `GRPKG001` packages, the `weblevels` caches, PNG/GIF/JPEG.
- **Sound.** FMOD (SDL_mixer on Linux).

Seihai's Issho plays 6.x through its own flat loop and does not try to be
this program. This directory does.

## Layout

| Directory | Original piece | State |
|---|---|---|
| `net/` | `TSocket`, the game connection, the session | **done**: wire integers, gen-5 codec (6.x long frames, raw-data escape), build rows, socket, connection, 178 warp |
| `cache/` | `weblevels` script cache | **done**: DES with Graal's key twist, CRC32, `GRESCR01` read and write |
| `tools/` | (none) | `quattro-session` logs a session; `quattro-play` runs the program in a window or headless (`--shot` writes the last frame as PNG) |
| `files/` | levels and packages | **done**: `GR-V1.00`–`1.05` (1.05 board layers), `GLEVNW01` text levels (start.nw, the offline tutorial), the 101 board packet, links, chests, signs; `GANI0001` sprite-mode ganis (sprites, steps, WAIT, SINGLEDIRECTION, ATTACHSPRITE/2, defaults). Packages and movie-mode ganis next |
| `draw/` | the draw passes and the window | **done**: the world passes in the original's order on a software canvas (shared with `common/torque/gui`), the lobby rule, an Xlib window and a headless window; players drawn from their gani with head, body, sword, shield and hats from the player's folder (`draw/assets`), the body in the player's five colours; the 6.x HUD (`draw/hud`: tabs, sword and glove, AP and MP bars, counters, hearts) |
| `shell/` | the program loop, `StartScript_*`, `GuiGraalCtrl` | **started**: the 50 ms loop, level name/board/links/chests from the session, window title per server, and the script host on `gs2::Machine` (140, 197 with the `GRESCR01` cache, 33/34, 190, 48), the GS2 weapon commands and events ("GS2 weapon scripts" below), and the GUI host: `StartScript_*` read from the player's own program file (`--program`), `MainMenuGui2D` as the content, the world drawn in its `GuiGraalCtrl`, mouse and keys from the window. The show-image emitters run each tick and draw through the painter (add, transparent, subtract, day-night). Next: the engine actions and `GuiShowImgCtrl` animations |
| `world/` | `TServerPlayer` and the props | **done**: the prop stream of 9 and 8 (the 2.22 table plus X2/Y2/Z2), the initial props after login, and the X2/Y2 movement diff each tick; walking against `arrays.dat` walls and chests with the six-point box, the corner nudge, and `push` with 38 `pushed,0`; the item keys (`world/actions`): S swings and cuts bushes (1 BOARDMODIFY), A lifts, throws (11) or grabs and pulls, D toggles the status bit, walking into a chest opens it (20); the server's 7 BOARDMODIFY is applied; Q and Tab toggle the status bit like D while no weapon is shown. The weapons (`world/weapons`): the weapon list (33, 34, 43 built-ins, 194 clears it) with the 2.05 selection rules; with a weapon shown D uses the selected one, a GS2 weapon through `onWeaponFired`, the built-in Bomb, Superbomb and Joltbomb by laying a bomb (4 BOMBADD, then 27 EXPLOSION and the blast's board changes), the Bow and the three magic shots by firing a shot (9 ARROWADD); other players' bombs, shots and explosions (11, 12, 19, 36) are drawn too; the scripts get `putbomb`, `shootarrow`, `shootfireball`, `shootfireblast`, `shootnuke`, `onKeyPressed` and a `player` object (x, y, dir, bombs, darts, rupees, hearts, ani, ...); Q opens the item list (`world/item_list`); blasts, shots, swings and 40 HURTPLAYER hurt the player, with knockback, death and coming back (`world/health`) The item drawing (`world/effects`, from the 6.03r7 item-drawing lab): the carried object over the head (bobbing with it, rising while lifted), `carry`/`carrystill`, a thrown object's 128 px flight with its shadow and its break into leaves, shards or sign pieces, a cut bush's leaves, and the item over an opened chest with its 13 ITEMDEL after 1.2 s |
| `gui/` | the GS2 controls | in `common/cpp/gs2` (`gui.hpp`, B4): one control tree for 4.x to 6.x; Quattro paints it on its canvas (`shell/gui_host`) |

The split with Track B: `common/cpp/gs2/` owns the bytecode loader, the
machine, `TGraalVar` objects and classes (namespace `gs2`). This program
feeds it script bytes (140, 197 and the cache) and registers its native
commands. Nothing here re-implements the machine.

## Builds

| Build | Token | Row | Folder |
|---|---|---|---|
| 6.03r7 Linux | `G3D0511C` | `net/profile.cpp` | `graal-6.03r7-G3D0511C` |
| 6.01r1 Linux | `G3D0108A` | `net/profile.cpp` | `graal-6.01r1-G3D0108A` |
| 4.04r2 Windows (the engine library's session) | `G3D17026` | `net/profile.cpp` | `graal-4.04r2-G3D17026` |
| 5.00r7 Windows (the engine library's session) | `G3D22067` | `net/profile.cpp` | `graal-5.00r7-G3D22067` |
| 5.12 Windows (the engine library's session) | `G3D14097` | `net/profile.cpp` | `graal-5.12-G3D14097` |
| 5.30r3, 5.31r4, Windows 6.00r2, 6.00r4, 6.03r7, 6.00 betas | | later (Track D3, D5) | |
| 6.11r1 Mac, 6.1.1.3 | set by the connector script | later (Track D4) | |

Linux first: those two are unpacked native binaries, so their notes are the
most complete.

The 4.x and 5.0 rows are used by `common/cpp/graalengine`, whose session
is this program's. 5.12 carries two codec rules of its own, set from its
row: a fifth login field (the quoted Windows version), and compressed
frames that are always zlib below the bzip2 size and stepped `len / 4`
rounded down (`Cipher::set_packed_round_down`; Graal_analysis
`protocol/v5v6-lab-play.md`, "5.12's cipher step count").

## Build and test

```
make -C common/cpp/quattro test
```

C++17, zlib and bzip2. The tests use loopback sockets only; no public
server is contacted. `quattro-session --list` prints the rows.

```
LAB_PW=... common/cpp/quattro/build/quattro-session --build 6.03r7 \
    --connect 127.0.0.1:14900 --account NAME --password-env LAB_PW
```

## Window size

The 6.03r7 row opens 1024 x 768, the size the real Linux client starts at
(HUD lab, 2026-11-12); other rows open 640 x 480, as Seihai's Issho does.
`quattro-play --size WxH` changes it. As in the real client, a bigger
window shows more of the level and nothing scales: tiles stay 16 pixels,
the HUD's left part keeps its x from the left edge and the hearts theirs
from the right. The HUD draws from the player's own `state.png` (and
`sprites.png` and `swordN.png`); with no `state.png` there is no HUD.
The 6.03r7 window title is the server name alone ("Lab Server"), and the
view centres on the player's middle (x + 1.5, y + 1.5), as the 2026-11-13
frames lab showed against the real Linux client; the HUD, tiles and
camera match it pixel for pixel there, at 640 x 480 to 1280 x 1024. The
view is clamped to the level while it fits; a view wider than the level
(1280) keeps the player centred with black either side. The Windows 6.x window and frame
were not measured.

## GS2 weapon scripts

The private weapon corpus has **not been run against this branch**. The survey's
coverage forecasts are not measured results. Synthetic scripts check the host's
cancellation and bounded-work rules: destroyed handlers cannot resume after
sleep/waitfor; nested arrays are limited to 10,000 cells and 32 levels; rectangle
queries reject nonfinite/negative dimensions and dimensions larger than one
64-tile board. Show-image coordinates and sizes must be finite and within one
million pixels, polygon inputs have at most 1,024 vertices, and tinted/polygon
drawing visits only the viewport. These are rebuild limits, not measured
original-client limits. Each show-animation has its own clock, independent of
other weapons using the same index.

Server weapons are GS2 bytecode on 5.24r3 and every 6.x build. The script
layer follows the implementation order of Graal_analysis
`npc-library/gs2-weapon-corpus-2026-11-14.md` (steps 1 to 7). The
machine-level part (opcodes, `scheduleevent`, `cancelevents`, `trigger`,
`destroy`, `md5`, `waitfor`) is in `common/cpp/gs2`; the rest is
`shell/scripts.cpp` (the trigger actions, `findweapon`, 48) and
`shell/weapon_api.cpp` (the commands that reach the game).

- **Server messages** (step 1): `triggerserver(kind, weapon, params...)`
  sends C->S 38 `serverside,<weapon>,<params>`, `triggeraction(x, y,
  action, params...)` sends 38 with the position in half tiles; both with
  CSV fields quoted as Seihai's gserver reads them. Server 48
  `clientside,<weapon>,<params>` queues that weapon's `onActionClientSide`
  with the params after the name; any other 48 action queues
  `onAction<action>` on every weapon.
- **Gani and hold** (step 2): `setani(gani)`, `replaceani(old, new)`,
  `freezeplayer(seconds)` (walk, item keys and D held), `disabledefmovement`
  / `enabledefmovement` (walk and item keys), `disableweapons` /
  `enableweapons` (D).
- **Events and boxes** (step 3): `say2(text)` opens a sign box (lines split
  at `#b`) that A, S, D, Enter or Space closes; `destroy()` on a weapon
  takes it off the list here, on a control off the screen, on a
  show-image hides it.
- **Show-images** (step 5): `showimg`, `showimg2`, `showtext`, `showtext2`,
  `showpoly`, `showani`, `showani2`, `findimg`, `hideimg`, `hideimgs`,
  `changeimgcolors`, `changeimgvis`, `changeimgzoom`, `changeimgpart`,
  `changeimgmode`, `getimgwidth`, `getimgheight`. Each show-image is an
  object whose members are its fields, numbered per script object.
- **The rest** (step 6): `findweapon(name)` (a call on it runs that
  weapon's function), `onwall`, `onwall2`, `onwater`, `onwater2` against
  `arrays.dat`, `keydown(i)` with GS1's indices ("0..10: up, left, down,
  right, S, A, D, M, tab, Q, P", the 1.41 commands.rtf), `keydown2(code)`,
  `getkeycode`/`keycode` with Windows virtual-key codes, `hideplayer`,
  `setfocus`/`resetfocus`; `play`, `play2`, `playlooped` and `stopsound`
  are logged until there is a sound layer; `seticonsize` does nothing.
- **Shots** (step 7): `setshootparams(params...)` and `shoot(x, y, z,
  angle, zangle, power, gani)` send C->S 40 as GServer-v2 reads it.
- **Events**: `onWeaponFired` (D), `onPlayerChats` (the chat bar, with
  `player.chat` set), `onKeyPressed(keycode, char)` and `onMouseDown("left"
  or "double", with `mousex`/`mousey` in level tiles and
  `mousescreenx`/`mousescreeny`) for input the GUI did not take,
  `onPlayerEnters` (each 6 level name), `onPlayerHurt(hearts)` and
  `onPlayerDies` from the own power prop, `onActionClientSide`.
- **`player`**: `x`, `y`, `z`, `dir`, `ani`, `chat`, `bombs`, `darts`,
  `rupees`, `hearts`, `fullhearts`, `mp`, `ap`, `id`, `account`, `nick`,
  `communityname`, `guild` (the nickname's last `(...)`), `head`, `body`,
  `level`, `gmap`, `attr[0..30]`, `colors[0..4]`, `freezetime` (-1 when
  not frozen), `paused`, `weapons` (the weapon objects), `weapon` (the
  selected one), and `client`/`clientr` kept as the script left them. A
  script's write to `x`, `y`, `z`, `dir`, `ani`, `chat`, `bombs`, `darts`
  or `freezetime` goes back to the player; `chat` is sent as prop 12.

Readings in this layer (none was seen from a 6.x client): the argument
forms are GS1's where the GS2 name is a GS1 command; `showtext2` and
`showani2` take z after y; show-images on layers 0 to 3 draw over the
level and its players in level tiles, layer 4 and up over the HUD in
window pixels, and a new one starts on layer 1; the sign box's layout;
which keys close it; `setani` drops its gani params, and a gani holds until
the walk changes it; `onPlayerHurt` gets the hearts lost; `shoot` uses 40
(PLI_SHOOT), not 48 (PLI_SHOOT2), and takes no ganiparams.

Not yet: other players' shots (175, 191) and `onActionProjectile`; the
shot's own flight; `showpoly2`; show-image text fonts (the built-in face
is used); `testnpc`, `findplayer`, `seteffect`, `showstats`, `putleaps`,
`serverwarp`, `isobject`, `enablefeatures`, the weapon-select switches and
the rest of the corpus's long tail (no name blocks more than 16 weapons).

## Rebuild choices (not the original's)

- Item keys: the stone's carry sprite was not seen, so lifting it sends
  only the first carry sprite, and a thrown stone breaks into nothing.
  The effect timings are the item-drawing lab's 50 ms series; the leaves'
  paths are rounded to one rule per corner, and where the pieces of a
  break start was measured facing right and down only. The gralat the
  server drops from a cut bush is a floor item and is not drawn yet. Only
  the green gralat was seen over a chest; other items use the Pascal
  clients' item sprite table. Carrying never pushes. Esc still quits with
  no GUI (the lab saw Esc toggle the status bit like D, Q and Tab).
  Through `Program::action` (the engine library's bindings), `doQ` does
  D and `doS2` (Space) does S.
- Weapons: with a weapon shown, Q and Tab open the client's own item
  list (`world/item_list`, 2.05's layout, arrows, Delete sending 29, Esc
  and the game keys closing it). A 6.x server usually sends its own list
  as a GS2 GUI script, which the scripts can open from `onKeyPressed`
  (every key down goes to every weapon script, with the Windows key code;
  that 6.x uses those codes is a reading). The window's colours, folders
  and scroll arrows were not read. Where a bomb or a shot starts, the
  55-tick fuse, the reach-2 blast of 11 ticks, a shot's tile a tick, and
  the bomb1.png cells are the 2.x Pascal rebuilds' readings, since no 6.x
  note gives them. After a bomb or an arrow the client sends its new
  count (props 4 and 5); that 6.x does so was not seen. The HUD does not
  draw the selected weapon. The GS1 command names are kept for GS2; the
  6.x command run is not copied out in the notes.
- Being hurt (`world/health`): the victim's client judges blasts, other
  players' shots and swings, and 40 HURTPLAYER, with 2.05's rules; the
  hurt lasts 31 ticks with 5 tiles of knockback, as the 6.03r7 lab saw.
  The shield's knock-back of an arrow with power 1 drops the arrow here.
  Dying sends hearts 0 and 14 CLAIMPKER; an arrow key brings the player
  back where the level was entered, with hearts by AP (the Pascal
  rebuilds' reading). Own blasts hurt their owner, as in 2.05.
- Stand-ins until the real art is drawn: tiles with no `pics1.png` are flat
  colours from their id; chests are boxes (6.03r7 draws none, as the
  real client does), and so is a player when no
  gani (not even `idle`) is in `--assets`. Body colours take the
  palette entries and the 20 colours of the Pascal clients; that 6.x uses
  the same entries was not seen in a lab. `PARAMn` sprites are not drawn yet. A gani steps once per 50 ms tick and starts over when the
  player's gani changes.
- Upper board layers treat tile 0 as empty; each layer's bit stream starts
  on a new byte. The 5.x note gives the layer count and boards, not these.
- `Options::asset_roots` are searched after `--assets`, laid out the same
  way (the tile sheet also in `levels/tiles/` and `levels/images/downloads/`).
  With `Options::download_files` (the engine library turns it on; `quattro-play`
  leaves it off) a tile sheet or player image no folder has is asked for once
  with C->S 23, and what comes back (102, or 68 / 102 / 69 for a large file;
  30 when the server has none) is kept in `<assets>/levels/images/downloads/`
  and drawn from at once. Asking for `pics1.png` so is a rebuild choice.
  Only a file the program asked for is kept, up to 8 MiB (a larger one is
  dropped with all its chunks and not asked for again); a name with a
  folder, drive or stream part (`/`, `\`, `:`, `..`), a control character or a
  Windows device name (`con.png`, `com1.png` ...) is never asked for or saved.
- Walls come from `arrays.dat` in `--assets` or an asset root (array 0 passable, array 1 liquids). With no `arrays.dat` every tile is passable; where 6.x reads its own table was not seen in the lab. The 0.0625 snap after a step is left out.
- GUI text uses the built-in Liberation Sans 16 px faces (the same tables as `common/GUiFont.pas`) in place of the player's TrueType faces; GUI bitmaps are read as PNG from `--assets` and its `gui`, `images` and `levels` folders. The playfield follows the player over the whole window and is clipped to the `GuiGraalCtrl`.
- The initial props send nickname "unknown", as the lab's 6.03r7 did with no nickname set.
- Update packages (the `4.04r2 Windows` row, `update_packages`): after each
  login `basepackage.gupd` twice, as 23, or as 47 with the CRC-32 of a copy
  saved before this run; `bigmap.txt` once per run on the Login session;
  the served package kept in `updatepackages/` and, on a game server, in
  `updatepackages/<name, space as %032>/` (Graal_analysis
  client-internals/live-behaviour-404.md). Other characters in a server
  name are escaped the same way (rebuild reading); the `FILE` list inside
  the package is not acted on.
- `Program::list_update` / `list_delete` keep the player list a 5.x launcher shows: every player the server names with 8, on any level, until a `DISCONNECT` (51) prop; leaving the level (50) keeps the row. Rows go out only when the nick, head, account, level, community name or first attribute changes. All rows are dropped at a warp (178) and when the link drops. `BuildProfile::last_prop` lets 5.12 read props 81 and 82 (community name); other rows stop at 80 as 2.22 does.
- Offline (`Program::start_offline`, the engine library's offline mode): a
  level or a gmap from `--assets`; a gmap's parts join at their edges as one
  board in global tiles (the 2.22 lab crossing), and a part's name is
  looked for in the gmap's folder first, then anywhere under `levels`. With
  no GS1 engine, the level NPCs' `addtiledef`, `setplayerprop`,
  `replaceani` and `setani` lines are read wherever they stand, not run.
- Gmaps (`files/gmap`): the `LEVELNAMES` grid, or the DungeonGenerator's
  short form rebuilt from `GENERATED` (Graal_analysis
  manual/03-formats/02-gmap.md); the heights and images are not read.

- Receive limits: 16 MiB per frame and 4 MiB of unfinished message. The
  original's were not read.
- The machine fields of the login line are made up: fixed MD5 hex of
  Squirrel-themed strings and a SquirrelOS kernel string, the shape the
  original sends (it hashes the machine). No machine is read.
- The PLI 50 size counts the id byte, the body and the newline; the note
  gives the cap, not what is counted.
