# Console engine (3.04 stage 1)

The TorqueScript console the 3.04 Linux client boots on: it runs the
install's compiled `.dso` scripts and keeps the state they rely on. This is
stage 1 of Graal_analysis `torque/rebuild-plan-3.04.md` and the execution and
object slice of [#172](https://github.com/squirelworks/graal-client-repro/issues/172)
under [#109](https://github.com/squirelworks/graal-client-repro/issues/109).
Drawing, waking controls and routing keys are later stages.

```
make -C common/torque/console/engine test    # unit tests and tq-boot
```

## What runs

- **Every opcode the 3.x scripts use** (Graal's DSO v33 table in
  Graal_analysis `torque/scripting.md`): functions, packages, `Parent::`
  calls, methods, `new` blocks with nested children, globals, locals, arrays,
  fields, string building and comparison, integer and float arithmetic, all
  branches. `TAG_TO_STR` and `BREAK` occur in no shipped 3.x script, so they
  fail instead of guessing.
- **Namespaces and packages.** Functions live in a namespace and a package
  layer. A named object's namespace links to its class namespace, which links
  to its parent class (`mainMenuGui` -> `GuiChunkedBitmapCtrl` -> `GuiControl`
  -> `SimGroup` -> `SimSet` -> `SimObject`). Packages layer over every
  namespace in activation order; `Parent::` goes to the next layer down, then
  to the parent namespace.
- **SimObject, SimSet, SimGroup**: ids, names (case-insensitive), dynamic
  fields, membership, `Name/Child` paths, group deletion, `RootGroup`,
  `$instantGroup`.
- **Stock functions and methods** the 3.04 scripts call (Graal_analysis
  `torque/study-torque-clients.md` section 5): console (`echo`, `exec`,
  `eval`, `export`, `setLogMode`, `setModPaths`, `quit`), packages, objects,
  `schedule`, files (`isFile`, `ExpandFilename`, `findFirstFile`, ...),
  string units and helpers, `FileObject`, and `ActionMap` binding data with
  `save()`.
- **The 3.04 class table** (`classes304.cpp`): the 31 classes the scripts
  create, and `GuiCanvas`.
- **Engine-owned prefs** (`prefs304.cpp`): variables the engine itself owns
  export quoted even when a script stores a number in them.

## Checked against the original

`lab/compare_304_boot.py` runs `tq-boot` on a 3.04 install and compares it
with the stage 0 capture of the original starting and quitting (the project's
lab files; neither is in this repository). Result on 2026-11-12:

| | Original | Rebuild |
|---|---|---|
| Console lines from the scripts | 8 | same |
| Compiled scripts run, in order | 35 | the same 33 in the same order; the other two wait on the GUI stage (below) |
| `graaldata/client/config.cs` (`moveMap.save`) | 19 lines | byte for byte |
| `graaldata/client/prefs.cs`, `common/client/prefs.cs` (`export("$pref::*")`) | 104 lines each | 102 the same; 2 the engine sets later (below) |

Known differences, each owned by a later stage:

- [ ] The video device's own log lines (`Activating the OpenGL display
  device...`, the GL attributes and extensions). `createCanvas` is a host stub
  here. GUI/video stage.
- [ ] `graaldata/languages/languageEnglish.cs` runs twice in the original,
  from `mainMenuGui::onWake` and the language menu's `onSelect`, when the
  canvas wakes its content. GUI stage.
- [ ] `$pref::Input::MouseEnabled` and `$pref::Video::appliedPref` export as
  `"1"`: the engine sets them during input and video start-up, after the
  scripts. Input and video stages.

## Boot runner

`build/tq-boot --root INSTALL --prefs DIR [--log FILE] [--trace FILE]
[--advance MS] [--exit]` boots an install: reads from `DIR` then `INSTALL`,
writes to `DIR`, prints the console, and with `--exit` runs `onExit()` the way
quitting does. The trace lists each script run and every host stub call.

The root `main.cs` is plain TorqueScript and no compiler is merged, so the
runner performs its steps itself: declare the empty `onStart`, `onExit` and
`parseArgs`, `setLogMode(6)`, the `Loading MODS` line, `setModPaths`, `exec`
of the two mods' `main.cs`, the `Engine initialized...` lines and `onStart()`.
When a compiler is merged it plugs into `Engine::compiler`, and the runner
execs the install's own `main.cs` instead.

Video functions and the other `GuiCanvas` methods the boot calls are host
stubs in `host/tq_boot.cpp`. They write to the trace only, never to the
console.

## Renderer seam (for stage 2)

- Objects: `Engine::find_object` (name, id or `Name/Child`),
  `SimObject::field` (every `.gui` and profile value is a dynamic string
  field), `members` in insertion order, `class_name` and `info`.
- Paths: `SimObject::source` is the script that created the object;
  `Engine::expand_path_from(source, "./defaultWindow")` resolves a field path
  the way the script meant it, and `FileSystem::read` returns the bytes.
- `GuiCanvas::setContent` stores the content and calls
  `Engine::on_set_content(canvas, content)`. Waking the content (`onWake`)
  belongs to the GUI stage and is not done yet.

## Evidence and policy

Observed, from the shipped scripts or the lab:

- Stack behaviour, from operand order in the 3.04 scripts: binary operators
  take the left operand from the top of the stack (`%i < $Game::argc` loads
  `$Game::argc` first); a field assignment is value, `ADVANCE_STR`, object,
  field, `TERMINATE_REWIND_STR`, save; an array name is the name,
  `ADVANCE_STR`, the index, `REWIND_STR`, with `ADVANCE_STR_COMMA` adding
  `_`; a `new` block pushes 0 first, `ADD_OBJECT` pushes the new id, a nested
  `END_OBJECT 0` pops it and the outer `END_OBJECT 1` leaves only the outer id,
  which the failure target finds as 0.
- An unused argument's identifier offset is at or past the end of the global
  string table (`mainMenuGui.cs.dso` has two in one header, at end and end + 6).
  The DSO reader now accepts both.
- Which file `exec` runs: the stage 0 open order loads shipped `.dso` files
  even where a plain source sits beside them, and compiles the `prefs.cs` the
  game wrote. The rebuild compiles a plain script found in the prefs
  directory, else loads the `.dso`, else compiles a shipped plain script.
- `export` writes `name = value;` lines with CRLF, sorted by name without
  case, string values quoted and escaped, numbers bare. `ActionMap::save`
  writes LF lines, key names lower case, the device without its number.
- `exec` writes nothing to the console log.
- Message formats (`Unable to find function`, `Unknown command`, the
  `Object` line after it, `Unable to find object`, `Unable to instantiate
  non-conobject class`, wrong argument counts, `Accessing local variable in
  global scope`) are strings of the 3.04 Linux engine. Which call prints
  which, and the `file (line)` prefix, are still to be compared in the lab.

Rebuild policy, not read from the original:

- Object ids start at 1027; `RootGroup` is 0 and not found by id.
- Every GUI control class links straight to `GuiControl`; intermediate stock
  classes are not read for 3.04.
- String units split on every separator, so two spaces make an empty word.
- `UINT_TO_FLT` and the `%d` form of integers are signed. `MOD` by 0 and the
  32-bit overflow case give 0. Floats print with `%g`.
- `STR_TO_NONE` leaves the current string; a function returns the current
  string at `RETURN`.
- Deactivating a package also deactivates the ones activated after it.
- `getRandom` uses a 32-bit LCG.
- Limits: 512 nested calls, 50 million instructions per script or function run,
  4096 stack entries. A runaway or malformed script stops with an error in
  the trace instead of crashing.

## Tests

`tests/engine_test.cpp` assembles each case by hand with
`tests/assembler.hpp` (opcode words and table entries written out, plus a DSO
v33 writer for the `exec` cases) and states the expected console lines,
values or files beside it. No original script, DSO or engine code is used.
The `torque-engine` workflow builds and tests this on Linux (also under
address and undefined-behaviour sanitizers) and Windows.

## Next

- [ ] Plug in the TorqueScript compiler (root `main.cs`, the prefs and key
  map files, `eval` and the F2 console).
- [ ] Stage 2: GUI canvas and controls on these objects, `onWake` and the
  two language loads.
- [ ] Stage 3: input through `ActionMap`, the console dialog.
- [ ] Compare the message formats and string-unit rules on the original.
