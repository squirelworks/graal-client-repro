# common/torque: parked Torque layer (target: v0.0.4)

Status on 2026-11-05: **on hold** by Squirrel's call ("hold off on torque, full speed ahead on less than V3"). Torque clients are targeted at the **v0.0.4** release. Nothing here is built or used by any client folder yet.

Plan: Graal_analysis `torque/rebuild-plan-3.04.md` (stages 0 to 5) and `torque/study-torque-clients.md`.

## What exists (stage 1, script VM, unfinished and never compiled)

- `TqCode.pas`: DSO v33 opcode constants, code block type, `.dso` loader (with big-endian float tables for PPC builds), string interning.
- `TqCompile.pas`: TorqueScript lexer, parser and code generator that emit the same opcodes, so `.cs` and `.dso` run through one interpreter.
- `TqVM.pas`: interpreter (typed int/float/string stacks, string stack slots), globals and locals, namespaces with package layers and `Parent::`, sim objects (ids from 1027, names, dynamic fields, groups, sets), `exec` path rules, native function registry.

## Next step when work resumes

1. Write `TqBuiltins.pas` (echo, exec, export, packages, string functions, isObject, FileObject, schedule, video stubs) and `TqGui.pas` (createCanvas, setContent/pushDialog with awaken order, GuiControl/ActionMap stubs, `Adventure` stubs).
2. Add `common/torque` to the `build.sh` unit path and get the three units compiling under FPC.
3. Add `graal-3.04-G3D03014/tests/TestScript304.dpr`: run the 3.04 install's `main.cs` and `.dso` files (path from an env var, skip when absent) and compare against the stage 0 captures: the `exec` order, the echo lines in `console.log`, and the exported `prefs.cs` and `config.cs`.

Stage 0 captures are kept outside this repo (lab material).
