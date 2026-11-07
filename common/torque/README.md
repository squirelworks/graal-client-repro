# common/torque: parked Torque layer (on hold, no target)

Status on 2026-11-05: **on hold** by Squirrel's call ("hold off on torque, full speed ahead on less than V3"). Torque is on hold with no target release. Nothing here is built or used by any client folder yet: `scripts/build.sh` does not put `common/torque` on its unit path.

Plan: Graal_analysis `torque/rebuild-plan-3.04.md` (stages 0 to 5) and `torque/study-torque-clients.md`.

## What exists (stage 1, script VM, unfinished)

The three units compile under FPC 3.2.2 in Delphi mode (`fpc -Mdelphi -Sh -Cr -Co -Fucommon -Fucommon/torque common/torque/TqVM.pas`), and a small script (functions, `@`/`SPC` concatenation, float results, `EvalString` from outside a script) runs. There is no test program in the repo yet; one comes with step 3 below.

- `TqCode.pas`: DSO v33 opcode constants, code block type, `.dso` loader (with big-endian float tables for PPC builds), string interning.
- `TqCompile.pas`: TorqueScript lexer, parser and code generator that emit the same opcodes, so `.cs` and `.dso` run through one interpreter.
- `TqVM.pas`: interpreter (typed int/float/string stacks, string stack slots), globals and locals, namespaces with package layers and `Parent::`, sim objects (ids from 1027, names, dynamic fields, groups, sets), `exec` path rules, native function registry.

## What this module is

The 3.04 Linux client is the Torque module. It is stock TGE 1.2 (console, sim objects, GUI canvas, fonts, themes, `ActionMap`) with Graal's 2D game as one console class, `GuiGraalCtrl`, not a redrawn menu and not a replacement of Torque's `Player`. Later clients drop pieces of that stock game layer (`Player`, vehicles, items, projectiles, datablocks). A module shaped like 3.04 can drop those for 4.20 and 5.12. It cannot be grown backwards out of 5.12.

The read of that binary is Graal_analysis `torque/engine-304.md`, and the console registrar is `torque/console-304.tsv` there. Counts include the command name and, on a method, the object id. `GuiGraalCtrl` has 31 methods. `moveUp` takes one script argument (count 3–3). `openServerList` takes none (2–2). `loadLevel` takes three (5–5). `updatePlayerProfile` takes ten (12–12). `setNickName`, `setAccountName`, `setLanguage` and `retrieveAccountFields` are not on the 3.04 table; nickname, account and language are `$pref::Graal::` variables. Those four methods are 3.153's.

Graal's draw types (`TDrawableObject` and the types under it, and `TGraalConnection`) are C++ inside the control. They are not console classes, so this module does not expose them to script.

## Next step when work resumes

1. Write `TqBuiltins.pas` (echo, exec, export, packages, string functions, isObject, FileObject, schedule, video stubs) and `TqGui.pas` (createCanvas, setContent/pushDialog with awaken order, GuiControl/ActionMap stubs, `Adventure` stubs for the 31 `GuiGraalCtrl` methods in the 3.04 note, not the 3.153 nickname methods).
2. Add `common/torque` to the `build.sh` unit path.
3. Add `graal-3.04-G3D03014/tests/TestScript304.dpr`: run the 3.04 install's `main.cs` and `.dso` files (path from an env var, skip when absent) and compare against the stage 0 captures: the `exec` order, the echo lines in `console.log`, and the exported `prefs.cs` and `config.cs`.

Stage 0 captures are kept outside this repo (lab material).
