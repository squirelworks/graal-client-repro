# common/torque: parked Torque layer, scaffold only

Status on 2026-11-05: **on hold** by Squirrel's call ("hold off on torque, full speed ahead on less than V3"). Torque is on hold with no target release. Nothing here is built or used by any client folder. `scripts/build.sh` passes `-Fu../../common` only. It does not pass `common/torque` or any directory under it, and it does not read `manifests/`.

This tree is the Torque surface Graal 3.x–5.0 actually linked, plus the names that linger after that. It is not an implementation. The script VM, the GUI and the network are not in these units.

## Parked script units (not on a manifest)

These three units are an unfinished stage-1 interpreter. They are not part of a version's link list, and no stub below uses them.

- `TqCode.pas`: DSO v33 opcode constants, code block type, `.dso` loader (with big-endian float tables for PPC builds), string interning.
- `TqCompile.pas`: TorqueScript lexer, parser and code generator that emit the same opcodes.
- `TqVM.pas`: interpreter, globals and locals, namespaces, a sim-object table, `exec` path rules, native function registry.

They are known to compile on their own under FPC 3.2.2 in Delphi mode. This scaffold does not add that command to `scripts/build.sh`.

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

`gameobject` is not in the 3.04 list. `game-tge` is not in the 4.2.0.8 or 5.0.0.7 3D lists. The cut, per program, is [CUTS.md](CUTS.md). `manifests/*.list` is the wire: one directory name per line. Those files are not include files and are not passed to fpc.

6.x is `quattro_lib` (common C++, not Torque). Unpacked 5.30 and 5.31 are already that program. Neither links a unit here. `common/cpp` is not part of this change.

## Notes this scaffold was read from

Graal_analysis, behaviour only:

- `torque/engine-304.md`, `torque/study-torque-clients.md`, `torque/engine-and-formats.md`, `torque/scripting.md`, `torque/network.md`, `torque/rebuild-plan-3.04.md`
- `torque/4208-launcher.md`, `torque/4208-engine.md`, `torque/4208-g3d.md`
- `torque/engine-5007.md`, `torque/g3d-5007.md`, `torque/launcher-5007.md`, `torque/engine-530r3.md`, `torque/engine-531r4.md` (the 5.0.0.7 and unpacked 5.30/5.31 reads). Each fact used from those notes is restated in the module README, so a missing file does not hide the cut.
- `client-internals/engine-600r2.md` for the 6.x cut

Issue comments for this layout are in [ISSUES.md](ISSUES.md). They are not posted.
