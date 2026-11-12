# common/torque: parked Torque layer, scaffold only

**Current C++ work (2026-11-09):** the old blanket hold below is historical.
The active reconstruction is tracked in #109/#172. `console/` now contains
a bounded C++ DSO v33 format reader, inspection tool and independent tests;
see [console/README.md](console/README.md). It does not execute scripts or
change either boot host. `gui/` now contains the C++ GUI foundations
(PNG and `.gft` readers, theme bitmap arrays, a software canvas); see
[gui/README.md](gui/README.md). The Pascal experiments remain parked. The older
module inventories below do not establish per-platform runtime behavior.

Status on 2026-11-05: **on hold** by Squirrel's call ("hold off on torque, full speed ahead on less than V3"). Torque is on hold with no target release. The Pascal units are not built by `scripts/build.sh`, and no client folder links them. `scripts/build.sh` passes `-Fu../../common` only. It does not pass `common/torque` or any directory under it, and it does not read `manifests/`. `common/torque/host304` is a C++ boot program with its own Makefile. `scripts/build.sh` runs that Makefile when it builds `graal-3.04-G3D03014`. `common/torque/host4208` is a C++ boot program with its own Makefile. `scripts/build.sh` runs that Makefile when it builds `graal-4.20r8-G3D20126`. The Pascal units stay off the Free Pascal unit path.

This tree is the Torque surface Graal 3.x–5.0 actually linked, plus the names that linger after that. It is not an implementation. The script VM, the GUI and the network are not in these units.

## Parked script units (not on a manifest)

These three units are an unfinished stage-1 interpreter. They are not part of a version's link list, and no stub below uses them.

- `TqCode.pas`: DSO v33 opcode constants, code block type, `.dso` loader (with big-endian float tables for PPC builds), string interning.
- `TqCompile.pas`: TorqueScript lexer, parser and code generator that emit the same opcodes.
- `TqVM.pas`: interpreter, globals and locals, namespaces, a sim-object table, `exec` path rules, native function registry.

They are known to compile on their own under FPC 3.2.2 in Delphi mode. This scaffold does not add that command to `scripts/build.sh`.

## What this module is

The 3.04 Linux client is the Torque module. It is stock TGE 1.2 (console, sim objects, GUI canvas, fonts, themes, `ActionMap`) with Graal's 2D game as one console class, `GuiGraalCtrl`, not a redrawn menu and not a replacement of Torque's `Player`. Later clients drop pieces of that stock game layer (`Player`, vehicles, items, projectiles, datablocks). A module shaped like 3.04 can drop those for 4.20 and 5.12. It cannot be grown backwards out of 5.12.

The read of that binary is Graal_analysis `torque/engine-304.md`. Argument counts, the 31 `GuiGraalCtrl` methods and the empty usage strings are in that note; the registry note is `torque/console-registrar.md`. Counts include the command name and, on a method, the object id. `GuiGraalCtrl` has 31 methods. `moveUp` takes one script argument (count 3–3). `openServerList` takes none (2–2). `loadLevel` takes three (5–5). `updatePlayerProfile` takes ten (12–12). `setNickName`, `setAccountName`, `setLanguage` and `retrieveAccountFields` are not on the 3.04 table; nickname, account and language are `$pref::Graal::` variables. Those four methods are 3.153's.

Graal's draw types (`TDrawableObject` and the types under it, and `TGraalConnection`) are C++ inside the control. They are not console classes, so this module does not expose them to script.

## Next step when work resumes

1. Write `TqBuiltins.pas` (echo, exec, export, packages, string functions, isObject, FileObject, schedule, video stubs) and `TqGui.pas` (createCanvas, setContent/pushDialog with awaken order, GuiControl/ActionMap stubs, `Adventure` stubs for the 31 `GuiGraalCtrl` methods in the 3.04 note, not the 3.153 nickname methods).
2. Add `common/torque` to the `build.sh` unit path.
3. Add `graal-3.04-G3D03014/tests/TestScript304.dpr`: run the 3.04 install's `main.cs` and `.dso` files (path from an env var, skip when absent) and compare against the stage 0 captures: the `exec` order, the echo lines in `console.log`, and the exported `prefs.cs` and `config.cs`.

## Modules

One directory per surface, each with a stub unit (no types, no allocated state) and a README. Kind is stock TGE 1.2, patched, or Graal-only.

| Directory | Unit | Kind | What it is |
|---|---|---|---|
| `console/` | `TqConsole` | stock | Console, `.dso` v33, native command registry. 3.x only. |
| `sim/` | `TqSim` | stock | `SimObject`, `SimSet`, `SimGroup`. |
| `gui/` | `TqGui` | patched | Stock GUI classes. The 4.x/5.0 2D engine draws them through the host. |
| `actionmap/` | `TqActionMap` | stock | `ActionMap`. 3.x, and the 3D DLL where the note names it. |
| `gbitmap/` | `TqGBitmap` | stock | `GBitmap` and the texture manager where that build has one. |
| `math/` | `TqMath` | stock | `Point2I`, `MatrixF`. |
| `game-tge/` | `TqGameTge` | stock | `ShapeBase`, `Player`, vehicles, items, projectiles. |
| `gameobject/` | `TqGameObject` | Graal-only | `GameObject`, a `SceneObject`. Not in 3.04. |
| `net-torque/` | `TqNetTorque` | patched | `GameConnection`. Stock demo in 3.04; Graal's protocol on the later 3D DLL. |
| `guigraal/` | `TqGuiGraal` | Graal-only | `GuiGraalCtrl`, and `GuiGraal3DCtrl` where that name exists. |

`gameobject` is not in the 3.04 list. `game-tge` is not in the 4.2.0.8 or 5.0.0.7 3D lists. The cut, per program, is [CUTS.md](CUTS.md). `manifests/*.list` is the wire: one directory name per line. They are not include files. `manifests/profiles.py` makes each one a build input: `check` holds every list to the CUTS.md table (exactly the modules marked **yes**), and `build` compiles a generated program that uses those modules' stub units with only their directories on the fpc unit path, so an unlisted module cannot link. `scripts/build.sh` still does not read them; the `torque-profiles` workflow runs `manifests/test_profiles.py` (#152).

6.x is `quattro_lib` (common C++, not Torque). Unpacked 5.30 and 5.31 are already that program. Neither links a unit here. `common/cpp` is not part of this change.

## Notes this scaffold was read from

Graal_analysis, behaviour only:

- `torque/engine-304.md`, `torque/study-torque-clients.md`, `torque/engine-and-formats.md`, `torque/scripting.md`, `torque/network.md`, `torque/rebuild-plan-3.04.md`
- `torque/4208-launcher.md`, `torque/4208-engine.md`, `torque/4208-g3d.md`
- `torque/engine-5007.md`, `torque/g3d-5007.md`, `torque/launcher-5007.md`, `torque/engine-530r3.md`, `torque/engine-531r4.md` (the 5.0.0.7 and unpacked 5.30/5.31 reads). Each fact used from those notes is restated in the module README, so a missing file does not hide the cut.
- `client-internals/engine-600r2.md` for the 6.x cut

What each component was written from, and the external material it does not use, is in [PROVENANCE.md](PROVENANCE.md) (#110).

Issue comments for this layout are in [ISSUES.md](ISSUES.md). They are not posted.
