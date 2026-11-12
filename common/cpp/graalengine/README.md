# graalengine: the 4.x/5.0 engine library

The 4.04r2 to 5.12 Windows clients are two programs: a Delphi launcher that
owns the window and every pixel, and `GraalEngine.dll`, which owns the
session, the canvas, the controls and the GS2 menus, and draws only by
calling back into the launcher. This folder is that engine library for the
rebuild (plan Track C1). The launcher half is
[`common/GEngineHost.pas`](../../GEngineHost.pas).

```
make            # build/libgraalengine.so, or build/GraalEngine.dll on Windows
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

## Where the rest plugs in

- The GS2 core (`common/cpp/gs2`, Track B) installs the start menus with
  `Engine::setGuiBuilder`; its controls derive from `graalengine::Control`
  or are held by one, and draw only through `graalengine::host::<Slot>(...)`
  (`src/host.hpp`). Until then `loadGraalGui` makes an empty
  `MainMenuGui2D` the content.
- The session (login, level, walk, chat) plugs in through
  `Engine::setConnector`, `setOfflineStarter` and `setTimer`.
- The 3D library fills the `GRAAL_BUILD_3D` slots (Track C4).

## Not yet

- [x] ~~The slot names checked one by one~~ against the `graal_set` names
  in the owner's unpacked 4.20r8 and 5.00r7 launchers and their engines'
  export tables (names only, read in the lab on 2026-11-12): the 94, the
  95 and the 19 3D-only names all match this list
- [ ] The GS2 menus on the canvas (B1 to B4), then the 4.04r2 launcher
  form drawing them (C2)
- [ ] The cursor drawn by the canvas, the hint, forcing the cursor on when
  the application is inactive
- [ ] Mouse press posting `double` / `doublemouse` on an even click count,
  and the level and server notification of a 2D click (needs the session)
- [ ] Flash panels, the microphone and the external windows: the launcher
  registers them and records the calls only
