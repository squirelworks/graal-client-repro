# guigraal

**Graal-only.** `GuiGraalCtrl` is the 2D game as one GUI control. `GuiGraal3DCtrl` is the later sibling. Neither is stock TGE. The `graal/` types (`TDrawableObject` and the types under it, `TGraalConnection`) are C++ inside the game. They are not console classes and this module does not expose them to script.

## The 3.04 control (stage 4)

`GuiGraal304` (C++) is `GuiGraalCtrl` for the 3.04 rebuild on the console
engine (`../console/engine`). The install's own `GraalGui.gui` creates it as
`Adventure`; the install's own scripts (`mainMenuGui.cs`, `ServerListGui.gui`,
`default.bind.cs`, ...) reach the game only through its 31 methods. The game
behind it is the existing 3.04 Pascal game (`graal-3.04-G3D03014/src`), built
as a shared library with a C interface (`Game304Lib.lpr`, `game304_abi.h`) and
loaded at run time (`pascal_game304.cpp`). The control talks to an abstract
`Game304`, so the tests run on a fake.

```
make -C common/torque/guigraal test        # guigraal-test (fake game)
make -C common/torque/guigraal lib all     # the Pascal library and tq-play (needs fpc)
sh common/torque/guigraal/tests/smoke.sh   # tq-play + the library, end to end
sh common/torque/guigraal/tests/online.sh  # menu to gserver login on loopback
```

`make test` also runs `frame-test`: a hand-built menu and game control drawn
by the GUI renderer, with clicks, typing, list selection, focus and the game
frame scaled into the control.

### graal304-torque

`build/graal304-torque [--root INSTALL] [--prefs DIR] [--game LIB]
[--steps FILE] [--seconds N] [--trace FILE] [--shot FILE.bmp]` is the windowed
program. It boots the install from its own `main.cs`
(`host/boot304.cpp`, shared with `tq-play`), draws the canvas content and the
pushed dialogs every 50 ms with `../gui` (`host/frame304.cpp`), and shows the
image in a window. The defaults are the program's own folder for the
install, `~/.graal304-torque` for prefs (`%APPDATA%\graal304-torque` on
Windows) and the game library beside the program. The canvas size is
`$pref::Video::resolution`, 800 × 600 if unset.

| System | Window | Program, library | Build |
|---|---|---|---|
| Linux | X11 (`host/window_x11.cpp`) | `graal304-torque`, `libGame304Lib.so` | `make lib all` |
| Windows | Win32 GDI (`host/window_win32.cpp`) | `graal304-torque.exe`, `Game304Lib.dll` | `make lib all` in an MSYS2 shell; the g++ and the Free Pascal must be the same CPU (both i386, as the release, or both x86_64) |
| macOS | Cocoa (`host/window_cocoa.mm`) | `graal304-torque.app` with `libGame304Lib.dylib` inside | `make lib all app` (Xcode command line tools and Free Pascal), or cross-built on Linux by `scripts/release/darwin-cross.sh` and `scripts/build.sh` |

`make PLATFORM=windows CXX=i686-w64-mingw32-g++ WINDRES=i686-w64-mingw32-windres`
cross-builds the Windows program from Linux. `tests/window.sh` runs the
program on a stand-in install, walks offline and checks the trace and the
window image (CI: Xvfb on Linux, the Windows runner's desktop).

Each window is a fixed-size frame around the canvas with only close and
minimise. They differ only where their systems do:

- Windows: a GUI program (no console window); started from a console it
  writes its console lines there. The exe is linked statically, so it needs
  no MinGW DLLs, and carries the shared manifest and version info
  (`graal-3.04-G3D03014/src/Graal304Torque.rc`).
- macOS: Cmd+Q and Cmd+W close the window as its close button does; the
  Option keys are Torque's `alt`.
- All three: keys held when the window loses focus are released (Windows,
  macOS), so the player does not keep walking; punctuation keys carry their
  Torque names (`comma`, `period`, ...) and type into text edits.

Rebuild policy, not read from the original:

- A click goes to the topmost control under the pointer (`../gui/mouse.cpp`):
  buttons, check boxes and radios run `command` then `onAction`; text edits
  take the first responder; a text list selects the row (a double click runs
  `altCommand`); a click on `GuiGraalCtrl` gives the keys back to the game.
  Inactive buttons do nothing. The layout is redrawn before each click, so a
  script that changed the content since the last frame is hit-tested as it
  is now.
- A double click is a second press within 400 ms and 5 pixels.
- The game frame is scaled into the control's box, nearest pixel; black when
  no game is running.

### Online test

`tests/online.sh` runs a fake listserver and gserver on loopback
(`tests/online/fake_servers.py`) and drives a small stand-in install's menu
functions with `tq-play`. It checks the list request token
(`G3D30123newmain`), that the account typed into `AccountEdit` reaches the
listserver, and that the gserver gets the 3.04 login (`G3D03014`, account and
password) for the Classic row.

### tq-play

`build/tq-play --root INSTALL --prefs DIR --game build/lib/libGame304Lib.so
[--steps FILE] [--seconds N] [--log FILE] [--trace FILE] [--shot FRAME.bmp]
[--no-draw] [--fast]` boots an install from its own `main.cs` (as `tq-boot`
does), adds the control, and runs a steps file: one TorqueScript statement per
line at a time in ms, standing in for clicks and keys. Every 50 ms frame
advances the engine's schedules and ticks the control, paced to the wall clock
unless `--fast`. `--shot` writes the game's last frame.

A lab run from the main menu to the game, through the same script functions
the buttons call:

```
0     NickEdit.setText("lab"); AccountEdit.setText("labacct"); PassEdit.setText("labpass");
0     switchToServerList();
3000  Adventure.selectServerCategory(2); ServerList.setSelectedRow(0);
3050  ServerListConnectButton::onAction(0);
8000  moveRight(1);
9000  moveRight(0);
9100  Adventure.setChat("hello");
```

### What each method does

| Method | Here | Source |
|---|---|---|
| `moveUp/Left/Down/Right(val)` | the key state to the local player | 304-adventure.md, observed |
| `doA/S/D/Q/P/M`, `doMicro` | traced; the 2D game has no sword, grab, items, map or voice yet | stage 5 |
| `setChat(text)` | `toall:` stripped and sent to all; `showname` not sent; `showap` sends an empty chat; anything else is the player's chat (prop 12); then `ChatBar.setText("")` | 304-adventure.md, observed |
| `setPassWord(pw)` | kept for the listserver and the login | observed name; storage is policy |
| `openServerList()` | `Canvas.setContent(ServerListGui)`, asks the listserver with `$pref::Graal::accountname` and the password | 304-net.md |
| list arrives | `ServerList.addRow(index, text)` for the servers of the current tab | 304-net.md (addRow); row layout is policy |
| list fails | console `Disconnected from serverlister`, `MessageBoxOK("Disconnected", why)`, back to `MainMenuGui` when no game is open | 304-net.md |
| `selectServerCategory(n)` | 0 Gold (`P `), 1 3D (`3 `), 2 Classic (no prefix), 3 Hosted (`H `); `U ` is never listed | button ids from `ServerListGui.gui`; prefixes from rebuild-plan-3.04.md |
| `selectServer(id)` | fills `ServerLanguage`, `ServerGraalVersion`, `ServerDescription`, `ServerHomepage` | 304-net.md names the fields; which goes where is policy |
| `connectToSelectedServer()` | the selected row needs more than 7 fields: 0 name (prefix stripped), 6 host, 7 port; the nickname pref is copied, `Canvas.setContent(AdventureGui)`, console `Connecting to the game server...`, login, `Done.` | 304-net.md |
| `serverDirectConnect(text)` | `host`, `host:port` or `host port`; 14802 when no port | the string goes straight in (304-net.md); parsing is policy |
| `startOfflineMode()` | only with no game connection: `AdventureGui`, the install's `offlinetutorial.gmap`, console `Player enters local level %s.` | 304-adventure.md |
| `updateLoadLevelFields()` | the level, x and y into `LoadLevelFilenameField`, `LoadLevelXField`, `LoadLevelYField` | 304-net.md |
| `loadLevel(file, x, y)` | offline: loads the level (from `levels/` or the root) at x, y; online: traced | 304-adventure.md |
| `privateMessageSend`, `playerListOpenPlayer`, `playerListProfile`, `updatePlayerProfile`, `updatePlayerMuted` | traced; no PM, player list or profile in the 2D game yet | stage 5 |
| `updateMidiVolume`, `updateMp3Volume`, `updateRadioVolume`, `updateMicroActivationLevel`, `updateGraalOptions` | traced; no sound unit yet | stage 5 |

The first wake of `Adventure` writes `Graal activated!` to the console
(304-adventure.md).

Rebuild policy, not read from the original:

- Row text is name, players, language, description, url, version, host, port
  (tab between). Only 0, 6 and 7 are observed; `columns = "5 150"` in the
  shipped list suggests a second visible column, taken as the players.
- The row id is the server's index in the listserver's list. Rows keep the
  category prefix in the name; it is stripped on connect.
- The default tab is Classic.
- A dead game link shows `MessageBoxOK("Disconnected", why)` (observed) and
  returns to `MainMenuGui` (policy).
- Each connect, offline start and level load starts a fresh game session
  (3.04 keeps one session object across wakes).
- The 3.04 tutorial gmap is `GENERATED` with no `LEVELNAMES`, which the game
  cannot name yet; offline mode then plays `offlinetutorial_b-2.graal` (named
  in 3.04's player unit) at (30, 30).

### Not yet

- [x] Draw the game's frame inside the canvas renderer (#257) and present it
  in a window (`graal304-torque`, X11).
- [x] The release program: the Linux 3.04 zip ships `graal304-torque` and
  the library (#273).
- [x] The Linux 3.153 zip ships `graal304-torque` and `libGame3153Lib.so`
  (`scripts/build.sh`, `graal-3.153-G3D28015/release-files`).
- [ ] The chat-focus key toggle on `ChatBar` and the hardcoded key codes the
  control reads itself (input stage, see `../console/engine` stage 3).
- [ ] Sword, grab, items, map, voice, PMs, the player list and profiles, sound
  (stage 5, 2D parity).
- [x] Walking on the offline tutorial (3.04's `picso.png` row rule). Online
  levels need 2.22's `arrays.dat` beside the install (see the 3.04 README).
- [x] Windows and macOS: Win32 and Cocoa windows, the library as
  `Game304Lib.dll` and `libGame304Lib.dylib`, and the Windows release zip.
- [x] The macOS release zips (x86_64 and arm64) carry `graal304-torque.app`.
  The app holds the program and the game library (`make app`; `APP_LIB`
  names the library) and finds the install in the folder that holds it.
  A start-up error (no `main.cs`, no library) shows a message box when no
  console reads the error, on Windows and macOS.
- [x] What the Linux lab on the real 3.04 install found missing: the
  Options dialog's `setVisible`, `setActive`, `performClick`, `getExtent`,
  `resize`, `getDisplayDeviceList`, `getResolutionList` and
  `getDesktopResolution` (`../console/engine/classes304.cpp`), the F2
  console's lines and input line (`../gui/render.cpp`), and the list step
  moving on to the `license.graal` hosts when the first listserver stays
  silent (`tests/online.sh` with `LIST_FALLBACK=1`).
- [ ] An app icon: no original icon to take it from yet (the Windows exe
  has the default icon for the same reason). The app is not signed beyond
  the linker's ad-hoc signature, so macOS asks once before opening it.

## 3.153 (Track A)

The same program and control run a 3.153 install (the Mac `GraalSetup`
`release` folder). An install with `scripts2D/main2D.cs` is taken for
3.153, and `setup_engine_304` switches to its profile:

- **`.dso` floats.** Its compiled scripts keep the float tables big-endian
  (the PPC build; Graal_analysis `torque/scripting.md`). The rest stays
  little-endian.
- **Scripts by name.** Every `exec` in 3.153 names only the file
  (`exec("main2D.cs")`, `exec("ServerListGui.gui")`), and the files sit in
  `scripts/`, `scripts2D/` and `scriptsgui/`. `Engine::exec_by_name` finds
  a bare name anywhere in the install. Bitmap names are resolved the same
  way (`graalscreen_backstone`). Rebuild policy: the match ignores case,
  and of several files with that name the one with the fewest folders wins.
- **Four more methods.** 3.153's table has `setNickName`, `setAccountName`,
  `setLanguage` and `retrieveAccountFields`, which 3.04's lacks
  (`engine-304.md`). The menu sets the fields before `openServerList` or
  `startOfflineMode`, and gets them back on wake. Rebuild policy: they are
  kept in the `$pref::Graal::` variables that 3.04 uses. An untouched
  nickname is `unknown`, the value the 3.153 lab capture sent.
- **Game library.** `libGame3153Lib.so` (`graal-3.153-G3D28015/src/Game3153Lib.lpr`)
  is the same C interface over the 3.153 units. It sends 3.153's login
  (`G3D28015`). `graal304-torque` picks it for a 3.153 install. The 3.153
  units now carry the 3.04 game fixes from #258 and #273 (log hook, chat,
  list hosts, walking by sheet type). The walking rules are the 3.04 ones,
  taken to hold for 3.153.

Tested here:

- The install's own scripts boot to `MainMenuGui2D` with no script errors.
- The menu draws in the window, with the background, buttons, labels, the
  nickname `unknown` and the edits.
- `tests/online.sh` with `GAME_LIB=libGame3153Lib.so GAME_TOKEN=G3D28015`
  sends a first frame with 3.153's layout as the Tiger lab capture shows it
  (5, 37, 34 bigmap and minimap).

Pixel check against the Tiger capture (2026-11-12): the 640 × 480 game
area cut from the capture against `graal304-torque --shot` on a clean
3.153 install (no file from 3.04), fonts from Liberation Sans:

- 98.76 % of pixels within 8 levels per channel, 98.65 % within 2;
- text boxes within a few pixels: "Welcome to Graal!" 119 wide against
  127, "Nickname:" 47 against 46, "Account:" 39 against 41 (Liberation
  Sans and its rasteriser against the Mac's Arial);
- the rest is data, not drawing: the account name and password the lab
  typed, and the pop-up's text (below).

Not yet:

- [x] Fonts. The Mac builds its `.gft` caches from system fonts at run time
  and ships none; the renderer builds them from a TrueType file the same
  way, at three quarters of the profile size (`../gui/README.md`, "Fonts
  without a cache"). No 3.04 file is used.
- [x] `graalscreen3d.jpg`, the logo, through the JPEG reader.
- [x] The text edit frames (`defaultTextEdit.png`, which the 3.153 profile
  names without `hasBitmapArray`) and the closed language pop-up.
- [x] A pixel comparison with the Tiger capture. The capture's game area is
  640 × 480 while the install's prefs say `800 600 Default`, so a
  resolution whose depth is not a number gives 640 × 480
  (`canvas_size_304`, rebuild policy). Result below.
- [ ] The language pop-up's text: the capture shows it empty, the rebuild
  shows `English`, the entry the scripts select.
- [ ] The first frame's 34 lines come once here; the capture has them twice.
- [ ] The 3D mode (protocol 19).

## Method table (all builds)

What the 3.04 table has: the 31 methods below, each registered with an empty usage string. The count includes the command name and the object. `moveUp` takes one script argument. `openServerList` takes none. `loadLevel` takes three. `updatePlayerProfile` takes ten.

| Method | Script arguments |
|---|---|
| `moveUp`, `moveLeft`, `moveDown`, `moveRight` | 1 |
| `doA`, `doS`, `doD`, `doQ`, `doP`, `doM` | 1 |
| `doMicro` | 1 |
| `setChat` | 1 |
| `setPassWord` | 1 |
| `openServerList` | 0 |
| `selectServer` | 1 |
| `selectServerCategory` | 1 |
| `startOfflineMode` | 0 |
| `connectToSelectedServer` | 0 |
| `serverDirectConnect` | 1 |
| `privateMessageSend` | 0 |
| `playerListOpenPlayer` | 1 |
| `playerListProfile` | 1 |
| `updateLoadLevelFields` | 0 |
| `loadLevel` | 3 |
| `updatePlayerProfile` | 10 |
| `updatePlayerMuted` | 1 |
| `updateMidiVolume`, `updateMp3Volume`, `updateRadioVolume`, `updateMicroActivationLevel`, `updateGraalOptions` | 0 |

`setNickName`, `setAccountName`, `setLanguage` and `retrieveAccountFields` are not on the 3.04 table. Nickname, account and language are `$pref::Graal::` variables. Those four methods are 3.153's.

`GuiGraal3DCtrl` is not a console class in 3.04. It is a name from 3.153 on.

| Version | Linked? |
|---|---|
| 3.04 | Yes. `GuiGraalCtrl` only. The shipped control is named `Adventure`. |
| 3.153 | Yes. Both names. The four account methods above are this build's, not 3.04's. |
| 4.04r2 3D | Not on the list. The marker scan hits `GuiGraal3DCtrl` in the 3D DLL and `GuiGraalCtrl` in the 2D engine. The 2D engine list is the one that links this unit. |
| 4.2.0.8 launcher | No. |
| 4.2.0.8 engine | Yes. Both names are engine types. While a script class is being resolved, a class named `GuiGraalCtrl` or `GuiGraal3DCtrl` is discarded, so script does not construct either. The 31-method table is not claimed for this DLL. |
| 4.2.0.8 3D | Not on the list. The 3D note does not name the control. The 2D engine owns the type. |
| 5.0.0.7 launcher | No. |
| 5.0.0.7 engine | Yes. The note lists `GuiGraalCtrl` and `GuiGraal3DCtrl` among the Graal types that DLL defines. |
| 5.0.0.7 3D | The name `GuiGraal3DCtrl` is a string in that DLL. The unit stays on the engine list, not a second copy. |
| 5.30 / 5.31 | Residual names, not this unit. Both `GuiGraalCtrl` and `GuiGraal3DCtrl` remain. `graal_set` is gone. |
| 6.x | Residual names, not this unit. Unpacked 6.00's GUI walk compares a control with `GuiGraalCtrl` and with `GuiGraal3DCtrl` and drops either when a parent flag is clear. There is no Torque scene behind the 3D name. |
