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
```

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

- [ ] Draw the game's frame inside the canvas renderer (#257) and present it
  in a window; `tq-play` writes it to a file.
- [ ] The chat-focus key toggle on `ChatBar` and the hardcoded key codes the
  control reads itself (input stage, see `../console/engine` stage 3).
- [ ] Sword, grab, items, map, voice, PMs, the player list and profiles, sound
  (stage 5, 2D parity).
- [ ] Walking on the offline tutorial: 3.04 ships no `arrays.dat`, and the
  built-in tile types block the `picso.png` tutorial board.
- [ ] Windows and macOS: the loader has a Windows branch but the library is
  only built and run on Linux so far.

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
