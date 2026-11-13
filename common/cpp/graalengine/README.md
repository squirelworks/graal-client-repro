# graalengine: the 4.x/5.0 engine library

The 4.04r2 to 5.12 Windows clients are two programs: a Delphi launcher that
owns the window and every pixel, and `GraalEngine.dll`, which owns the
session, the canvas, the controls and the GS2 menus, and draws only by
calling back into the launcher. This folder is that engine library for the
rebuild (plan Track C1). The launcher half is
[`common/GEngineHost.pas`](../../GEngineHost.pas).

```
make            # build/libgraalengine.so, or build/GraalEngineRepro.dll on Windows
make test       # recording-host tests, then the export check
```

`scripts/build.sh graal-4.04r2-G3D17026` builds the library and copies it
next to `Graal404`; `TestEngineHost404` loads it from there.

## What it was written from

Graal_analysis, behaviour only; nothing from a decompile is kept here.

| Fact | Note |
|---|---|
| The launcher resolves one `graal_set<Name>` per slot, calls each, then `graal_engineInitialize`; zero means warn and quit | `torque/4208-launcher.md`, `torque/5007-launcher.md` |
| 94 slots on the 4.x launcher; the 5.0 launcher adds eight and drops seven; the engine names 19 more that the 3D library fills | `torque/4208-launcher.md`, `torque/5007-launcher.md`, `torque/engine-4208.md` |
| Each setter stores a pointer; a draw helper calls it only when set | `torque/4208-launcher.md` |
| The launcher calls `renderGraalCanvas` each frame and never `renderGraal` | `torque/4208-launcher.md` |
| `renderFrame`: clip to the screen, fit the main controls, timer, then render each visible child | `torque/4208-engine.md` |
| `setContentControl` makes a control the screen; `MainMenuGui2D` when setup passes | `torque/4208-engine.md` |
| Keys and mouse arrive as `invokeGraalKeyboardEvent` / `invokeGraalMouseEvent` and become canvas input events; mouse button 0, 1 `middle`, 2 `right` | `torque/4208-engine.md` |
| A server name whose second character is a space loses two characters; `3 ` selects 3D and the engine asks the launcher through `StartGraal3D` | `torque/4208-engine.md`, `torque/network.md` |
| `graal_engineInitialize` records the exe path on the first call and reads `license/license.graal` as lines; a second call only resets the script environment | `torque/5007-engine.md` |
| An empty window rectangle becomes 640 x 480 | `torque/4208-launcher.md` |

## What is the rebuild's own

- **The argument lists.** The notes recover the slot names and their jobs,
  not their arguments (the registration calls lose them), and nothing here
  loads an original library or an original launcher. The arguments in
  [`include/graalengine_slots.def`](include/graalengine_slots.def) are this
  rebuild's, chosen so the GS2 controls can draw with them. `GRAALENGINE_ABI`
  guards them: the launcher refuses a library with another value.
- **Textures** are engine-owned `graal_texture` records with ARGB pixels;
  the launcher may cache its own copy under `host_data`.
- **The `graalengine_*` exports** (interface version and slot list) are not
  in the original. The launcher uses them to register exactly the slots of
  its build and to report any it has no function for.
- **The engine's start-up log line** through `LogGraalMessage`.
- `openGraalServerList` dials the licence's first host as `Login`
  (`torque/5007-engine.md` adds "when an account and a password are
  already set and no client exists yet"; that check comes with the
  session).

## The start menus (C2)

The GS2 machine (`common/cpp/gs2`) is linked into the library.
`graal_engineInitialize` makes it; `loadGraalGui` reads the `StartScript_*`
the player's own engine file carries and runs them in the order
`torque/4208-engine.md` gives:

| Step | Scripts | Kept? |
|---|---|---|
| 1 | `Profiles` | run, then dropped |
| 2 | the canvas | |
| 3 | `MainMenu`; `MainMenuGui2D` becomes the content | kept |
| 4 to 7 | `OptionsWindow`, `PlayerProfile`, `LoadLevelGui`, `QuitDialog`, `MessageBoxDialog`, `SelectFileDialog` | kept |
| 8 | `MoveMap2D`, `MoveMap3D` | run, then dropped (and again on each later `loadGraalGui`) |
| offline, 2D connect | `GraalGui`; `GUIContainer` becomes the content | kept |
| 3D connect | `GraalGui3D` | kept |

A kept script goes on a universe variable of its name, made only if none
exists. Each frame's timer runs one 2D pass of the machine (the clock
steps 0.05, the launcher's 50 ms frame).

The engine file is `GRAAL_ENGINE_FILE` if set, else the install's own
`GraalEngine.dll`, else the launcher's exe. It is read at run time;
nothing from it is kept here. That is also why the rebuilt library is
called `GraalEngineRepro.dll` on Windows: dropping it into an install must
not replace the player's original.

The engine commands those scripts call, through `gs2::EngineHost`:

| Command | Does |
|---|---|
| `echo` | `LogGraalMessage` |
| `openURL` | `OpenURL` |
| `keydown` | the key state from `invokeGraalKeyboardEvent` |
| `getResolutionList` | the current screen size (the original lists DirectDraw's modes) |
| `Adventure_setAccountName`, `setPassWord`, `setNickName`, `setChat` | kept as the account for the session |
| `Adventure_updatePlayerProfile`, `updateAccountField`, `updatePlayerMuted`, the volume calls | kept by name until the session sends them on |
| `Adventure_openServerList` | dials the licence's Login host |
| `Adventure_startOfflineMode` | offline mode, as `startOfflineMode` |
| `Adventure_openExternalOptions` | `OpenExternalOptions` |
| `Adventure_selectPath` | `ShowSelectPathDialog` |
| `Adventure_getInstallationPath` | the exe path given to `graal_engineInitialize` (the 5.x setup dialog compares its base name with `setup`) |
| `Adventure_quit` | `PrepareShutdownGraal`, then `ShutdownGraal` |

Checked against the player's own 4.04r2 `GraalEngine.dll` (`make test`
with `GRAAL404_ENGINE` set): all 14 scripts load, the kept seven are on
the universe, the dropped ones are not, `MainMenuGui2D` is the content and
offline mode adds `GraalGui`. The only commands the scripts still miss are
the GUI ones B4 brings (`addcontrol`, `addRow`, `clearRows`,
`setSelectedRow`, the key modifiers); no engine command is missing.

## The menus drawn (C2)

With no GUI builder set, `loadGraalGui` makes the B4 GS2 screen
(`common/cpp/gs2/gui.hpp`) on the engine's machine, so the start scripts'
`new GuiControl(...)` builds real controls. A script object made the
content (`MainMenuGui2D`, `GUIContainer`) becomes that screen's content,
and the canvas shows one control, `GS2Screen`, that draws it and takes
its input (`src/gui_host.cpp`):

| Piece | Does |
|---|---|
| `TextureCache` | finds a picture by name in `levels3d/gui`, `levels/gui`, then the install root, case ignored, `.png`/`.jpg`/`.gif`/`.bmp` tried when there is no extension; misses are remembered. PNG through `torque/gui/image.cpp`, the rest through the vendored `stb_image` (`common/cpp/third_party/stb`) |
| `SlotPainter` | the GS2 painter on the slots: `SetClippingRectangle`, `FillScreenRectangle`, `DrawText`, `GetTextWidth`, `GetTextHeight`, `DrawGraphics`, `DrawGraphicsStretched` (tiled `DrawGraphics` on 5.0, which has no stretch slot); bitmap arrays split as Torque does |
| `ScreenControl` | left press to `Screen::mouseDown`, key press and release by Torque key name to `keyDown`/`keyUp`; key bindings that name no function go to `setEngineActionHandler` |

Checked against the player's own 4.04r2 `GraalEngine.dll` (`make test`
with `GRAAL404_ENGINE`): the main menu draws (59 fills, 10 texts in a
frame), a click in the Nickname box and typing sets the nickname through
`Adventure_setNickName`, and a click on Offline Test starts offline mode.

## The 2D session (C2)

`connectToGraalServer` with no connector set starts the engine's own 2D
session (`src/session.cpp`). 4.04r2 is gen 5 on the wire, as the Quattro
program is, so the session is that program's (`common/cpp/quattro`): its
connection under the `4.04r2 Windows` build row (token `G3D17026`, `win`
and three machine fields, no ping answer, never 39), the Login server and
the 178 hand-on, the level, the player's props, walking and the world
passes. The engine adds what the menus give it:

| From | Becomes |
|---|---|
| `Adventure_setAccountName`, `setPassWord`, `setNickName` | the login and the nickname prop |
| GraalGui's `GraalControl` (`GuiGraalCtrl`) | where the world frame is drawn (`DrawGraphics`, or stretched to the control) |
| the MoveMap2D bindings `moveUp2D`, `moveDown2D`, `moveLeft2D`, `moveRight2D` | the held arrows |
| the chat bar's `Adventure_setChat` | the player's chat (prop 12) |
| `enableGraalScriptedControls` | the scripts' `scriptedcontrols`, which GraalControl reads on wake to push MoveMap2D (on until the launcher says otherwise) |

Checked on loopback (`make test`, a fake gen-5 server): the login line,
the hand-on, the level, the props with the nickname, walking and the chat.
With the player's own 4.04r2 `GraalEngine.dll` (`GRAAL404_ENGINE`) the
world shows in `GraalControl` and the right arrow walks through the real
MoveMap2D binding.

## Which build (rebuild only)

`graalengine_setBuild(label)`, called before `graal_engineInitialize`,
names the launcher's build: `4.04r2` (the default), `5.00r7` or `5.12`. It
picks the session's wire row (`common/cpp/quattro/net/profile.cpp`) and
the GS2 opcode profile (4.2 for 4.x, 5.0 for 5.x). The original library
had no such call; each was built for its own launcher. The 5.0 launcher
has no `LogGraalMessage`, so with no log slot the engine's lines go to
stderr when `GRAALENGINE_LOG` is set, and the playfield is drawn with
`DrawGraphics` (no stretched draw on 5.0).

Each login (the first server, then every warp) is passed to the
launcher's `OnServerLogin` with the server's name; the 5.x launcher titles
its window with it.

The session's files: the install (the launcher's folder), then
`graal-assets/<build>/` and `graal-assets/common/` next to it, as the
Pascal launchers search (`common/GAssetDirs.pas`). A tile sheet or player
image none of them has is asked for from the server with 23 and kept in the
install's `levels/images/downloads/`, as a 5.x install keeps `sprites.png`.

`make test` runs the loopback session for 4.04r2 and for 5.12 (5.12's
login line with its fifth field, every frame zlib with its cipher step,
the hand-on, level, walk and chat). With `GRAAL512_ENGINE` set to the
player's own 5.12 `GraalEngine.dll`, the 5.12 run also checks the real
GraalGui's playfield and the arrow key, as `GRAAL404_ENGINE` does for
4.04r2.

## The show-images (C2)

A `GuiShowImgCtrl` is drawn by the engine (`src/showimg.cpp`). One with
an `ani` plays that gani (the first comma field) with the control's
`actor` (head, body, `attr[n]`, as the script sets them), facing `dir`,
its top left at `offsetx`, `offsety`, one step every 50 ms frame. The
Quattro program's actor pass draws it into a picture the size of the
control, from the install's `levels/ganis`, `heads`, `bodies` and the
rest, and `DrawGraphics` puts it on screen. Each frame also runs the
screen's emitters, and each particle is turned, scaled and tinted here
into a picture of its own (the launcher keeps the 2D matrix slot but
does not apply it). It is blended by its alpha whatever its mode,
because the launcher has no additive or subtractive draw.

On the player's own 4.04r2 menu: the character walking bottom left
(StartAni1), the lamp post (StartAni2), the smoke (StartAni4) and the
monster by the title (StartAni6).

## Where the rest plugs in

- The GS2 controls (Track B4) register their object factory and GUI
  commands on `Engine::machine()` from `Engine::setGuiBuilder`, which runs
  before the start scripts, and map a script object to its control with
  `Engine::setControlResolver`. Controls derive from `graalengine::Control`
  or are held by one, and draw only through `graalengine::host::<Slot>(...)`
  (`src/host.hpp`). Without a builder the B4 screen above is used.
- Other session code can still take over through `Engine::setConnector`,
  `setOfflineStarter` and `setTimer`.
- The 3D library fills the `GRAAL_BUILD_3D` slots (Track C4).

## Not yet

- [x] ~~The slot names checked one by one~~ against the `graal_set` names
  in the owner's unpacked 4.20r8 and 5.00r7 launchers and their engines'
  export tables (names only, read in the lab on 2026-11-12): the 94, the
  95 and the 19 3D-only names all match this list
- [x] ~~The start scripts run on the engine's machine, with the engine
  commands they call~~ (C2)
- [x] ~~The menus drawn: the GUI commands and controls (B4)~~
- [x] ~~Text at the script's font and size~~ (the 4.04r2 launcher reads
  Arial with GTrueType; Liberation Sans on Linux)
- [x] ~~Login, level, walk and chat~~ on the Quattro session (above)
- [x] ~~`GuiShowImgCtrl` animations~~ (above); particle blend modes other
  than alpha need a launcher slot
- [ ] Offline mode's level, the other GraalGui keys (`doA`, `doS`, `doD`,
  the map and item menus) and the 3D connect
- [ ] `Adventure_saveGraalOptions`, `Adventure_installGraal` and the
  `Adventure_selectFile*` calls (refused with the engines' "not found"
  error until they are written); the setup test (always passes here)
- [ ] The cursor drawn by the canvas, the hint, forcing the cursor on when
  the application is inactive
- [ ] Mouse press posting `double` / `doublemouse` on an even click count,
  and the level and server notification of a 2D click (needs the session)
- [ ] Flash panels, the microphone and the external windows: the launcher
  registers them and records the calls only
