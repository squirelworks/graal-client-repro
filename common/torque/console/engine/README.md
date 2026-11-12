# Console engine (3.04 stage 1)

The TorqueScript console the 3.04 Linux client boots on: it runs the
install's compiled `.dso` scripts and keeps the state they rely on. This is
stage 1 of Graal_analysis `torque/rebuild-plan-3.04.md` and the execution and
object slice of [#172](https://github.com/squirelworks/graal-client-repro/issues/172)
under [#109](https://github.com/squirelworks/graal-client-repro/issues/109).
Stage 3 (input and the F2 console) is `input304.cpp`, below. Drawing is
stage 2 (`../../gui`).

```
make -C common/torque/console/engine test    # engine and input tests, tq-boot
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
- **Text lists** (`textlist304.cpp`): `GuiTextListCtrl` rows, selection and
  sorting, with `onSelect(id, text)`; the server list fills it (stage 4,
  `../../guigraal`).
- **Engine-owned prefs** (`prefs304.cpp`): variables the engine itself owns
  export quoted even when a script stores a number in them.

## Checked against the original

`lab/compare_304_boot.py` runs `tq-boot` twice on a 3.04 install (the stage
0 capture was the original's second start) and compares the second run with
the capture of the original starting and quitting (the project's lab files;
neither is in this repository). Result on 2026-11-12:

| | Original | Rebuild |
|---|---|---|
| Console lines from the scripts | 8 | same |
| Scripts run, in order: the root `main.cs`, 35 compiled, the written `prefs.cs` and `config.cs` | 38 | the same 38 in the same order |
| `graaldata/client/config.cs` (`moveMap.save`) | 19 lines | byte for byte |
| `graaldata/client/prefs.cs`, `common/client/prefs.cs` (`export("$pref::*")`) | 104 lines each | 102 the same; 2 the engine sets later (below) |

Known differences, each owned by a later stage:

- [ ] The video device's own log lines (`Activating the OpenGL display
  device...`, the GL attributes and extensions). `createCanvas` is a host stub
  here. GUI/video stage.
- [x] `$pref::Input::MouseEnabled` exports as `"1"` although `defaults.cs`
  stores 0: input start-up (`start_input_304`, from `createCanvas`) sets it
  after the prefs scripts ran.
- [ ] `$pref::Video::appliedPref` exports as `"1"`: the engine sets it during
  video start-up, after the scripts. Video stage.

## Boot runner

`build/tq-boot --root INSTALL --prefs DIR [--log FILE] [--trace FILE]
[--advance MS] [--input FILE] [--exit]` boots an install: reads from `DIR` then `INSTALL`,
writes to `DIR`, prints the console, and with `--exit` runs `onExit()` the way
quitting does. `--input` then plays a key script (`key f2`, `type echo("x");`,
`key enter alt`, `down`/`up`, `advance MS`; see `host/tq_boot.cpp`), and a
`quit();` typed into the console ends the run through `onExit()`. The trace
gets one `input ...` line per key with where it went. The trace lists each script run and every host stub call.

Plain scripts go through the TorqueScript compiler (`../compiler`, #254),
plugged into `Engine::compiler`: the runner execs the install's own root
`main.cs`, and a second start compiles the `prefs.cs` and `config.cs` the
first one wrote, as the original does.

Video functions and the other `GuiCanvas` methods the boot calls are host
stubs in `host/tq_boot.cpp`. They write to the trace only, never to the
console.

## Input and console (stage 3)

`input304.cpp`, registered by `register_input_304` after the classes.

- **Routing.** The host turns each key into an `InputEvent` (device, Torque
  key name, shift/ctrl/alt, press or release, the typed character) and calls
  `Engine::process_input`. A press goes to `GlobalActionMap` first, then to
  the canvas's first responder, then to the pushed maps from the top
  (`moveMap.push()` in `AdventureGui::onWake`, `pop()` in `onSleep`). The
  release goes to the binding that took the press, even if its map was
  popped since. `bind` calls the function with `1` and `0`; `bindCmd`
  evaluates the make and break strings (an empty make string still takes the
  key, so `alt enter` and `escape` run on release). Deleting a map unpushes
  it (`restoreDefaultMappings` and `config.cs` both start with
  `moveMap.delete()`).
- **Canvas dialogs.** `pushDialog(ctrl [, layer])` and `popDialog([ctrl])`
  keep `Engine::dialogs` sorted by layer (push order within a layer), wake
  and sleep the dialog, and move the keys: a dialog that lands on top gives
  them to its first `GuiInputCtrl` or text edit; popping it hands them to the
  top dialog that has one, so a remap dialog pushed from under the console
  gets the next key once F2 closes the console. The CanvasCursor package's
  two-argument `pushDialog` override still reaches these through `Parent::`.
- **F2 console.** `ToggleConsole` from the shipped `ConsoleDlg.gui` pushes the
  dialog at layer 99; `ConsoleEntry` (`GuiConsoleEditCtrl`) takes typed
  characters, Backspace, Delete, Left, Right, Home and End, Up and Down walk
  its `historySize` lines, and Enter runs its `altCommand`
  (`ConsoleEntry::eval()`), which echoes `==>` and the line and runs it
  through `eval` and the compiler. Text edits keep their text in the `value`
  field (`getValue`/`setValue`). `GuiConsole` draws
  `Engine::console_buffer`, which the host fills from its print callback with
  `add_console_text`.
- **Remap dialog.** `OptRemapInputCtrl` (`GuiInputCtrl`) gets the next key
  that is not a modifier on its own and calls its script
  `onInputEvent(device, action)` with `keyboard` and the key name (modifiers
  first: `ctrl k`). Binding a function to a new key unbinds its old one. The shipped script binds it on `moveMap`, and
  `optionsDlg::onSleep` or `onExit` saves `config.cs` through
  `ActionMap::save`.
- `activateKeyboard` and `deactivateKeyboard` are registered and do nothing
  (the original prints nothing for either); `toggleFullScreen` is a host
  stub. The console only calls the keyboard pair when `$enableDirectInput`
  is set, which no 3.04 script does.

## Renderer seam (for stage 2)

- Objects: `Engine::find_object` (name, id or `Name/Child`),
  `SimObject::field` (every `.gui` and profile value is a dynamic string
  field), `members` in insertion order, `class_name` and `info`.
- Paths: `SimObject::source` is the script that created the object;
  `Engine::expand_path_from(source, "./defaultWindow")` resolves a field path
  the way the script meant it, and `FileSystem::read` returns the bytes.
- `GuiCanvas::setContent` puts the old content to sleep (`onSleep`), wakes
  the new one (the control's script `onWake`, then its children; the order is
  rebuild policy), then calls `Engine::on_set_content(canvas, content)` for
  the renderer. Controls keep `text` and `value` in fields (`setText`,
  `getText`, `setValue`, `getValue`); `GuiPopUpMenuCtrl` keeps its entries
  (`add`, `clear`, `sort`, `findText`, `setSelected`, which calls the script
  `onSelect(id, text)`). With that, `mainMenuGui::onWake` runs as in the
  original: it lists the language files, selects English and runs
  `languageEnglish.cs` twice, matching the stage 0 open order.

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
- Input (stage 3) is written from what the shipped 3.04 scripts expect: the
  `moveMap`, `GlobalActionMap` and `bindCmd` lines in `default.bind.cs`,
  `ToggleConsole` and `ConsoleEntry::eval` in `ConsoleDlg.gui`, and
  `OptRemapInputCtrl::onInputEvent`, `getMapDisplayName` (which wants the
  device `keyboard` with no number) and `optionsDlg::onSleep` in
  `optionsDlg.cs`. The lab key script below checks the rest.
- Message formats (`Unable to find function`, `Unknown command`, the
  `Object` line after it, `Unable to find object`, `Unable to instantiate
  non-conobject class`, wrong argument counts, `Accessing local variable in
  global scope`) are strings of the 3.04 Linux engine. The lab key script
  (below) matched the first four, wrong argument counts and the
  `<input> (0):` prefix for console input; `Unable to instantiate` and the
  global-scope message outside `eval` are not compared yet.

Rebuild policy, not read from the original:

- Lab-observed for input (table above): `GlobalActionMap` before the
  remap dialog's `GuiInputCtrl`, binding a function again unbinding its old
  key, `enter` stored as `return`, `save()` to the console printing only the
  binds, `eval` sharing its caller's locals, and the `(null)::` prefix for a
  global function's argument-count message.
- Input order between the canvas and the pushed maps, releases following
  their press, exact modifier match (`shift a`
  does not run a binding for `a`), left and right modifiers counting as one,
  key repeat reaching only text edits, where the keys go after a push or a
  pop, the `ctrl k` modifier order in `GuiInputCtrl` and the console history
  rules (no repeat of the newest line) are rebuild policy.
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

## Lab check for input (stage 3)

`lab/keys-304.txt` is one key script for both sides: `lab/drive_304_keys.py`
plays it into the original 3.04 client with `xdotool` in the lab VM and
collects its `console.log` and `config.cs`; `lab/compare_304_input.py`
plays it into `tq-boot` and compares the console lines from the first typed
line on, and `config.cs` byte for byte. It covers `echo("x");`, the failing
call messages above, console history, a remap through the shipped dialog
with the console closed over it, and Escape inside the remap dialog.

Run on 2026-11-12 in the Linux lab VM (the original's second start, keys
played with `xdotool` under Xvfb):

| Check | Original 3.04 | Rebuild |
|---|---|---|
| `a` at the main menu | nothing (only `GlobalActionMap` is active) | same |
| F2, `echo("x");` | `==>echo("x");`, `x` | same |
| `nosuchfunction();` | `<input> (0): Unable to find function nosuchfunction` | same |
| `NoSuchObject.foo();` | `<input> (0): Unable to find object: 'NoSuchObject' attempting to call function 'foo'` | same |
| `Canvas.noSuchMethod();` | `Unknown command noSuchMethod.` and the `Object` line | same message; the object line differs (below) |
| `echo();` | `(null)::echo - wrong number of arguments.`, `usage: echo(text [, ... ])` | same (fixed here) |
| `activateKeyboard();` | registered, prints nothing | same (fixed here; Graal_analysis said it was unregistered) |
| `%local = 1;` | nothing: `eval` runs in `ConsoleEntry::eval`'s frame | same (fixed here) |
| Up, Enter | runs the last line again | same |
| `GlobalActionMap.save();` | the bind lines only; `alt enter` saved as `alt return` | same (fixed here) |
| Remap Up to K, console closed over the dialog | `config.cs` loses `up`, gains `k` as its last line | byte for byte (fixed here) |
| Escape inside the remap dialog | `GlobalActionMap` runs `escapeFromGame`: the quit box opens, the remap dialog stays (`1 1 1`) | same |

Still different, owned elsewhere:

- [ ] The `Object` line after `Unknown command` on `Canvas`: id 1050 and
  `Canvas -> GuiCanvas -> GuiCanvas -> GuiControl -> ...` in the original,
  1028 and one `GuiCanvas` here. Object count and the canvas's class chain
  (stages 1 and 2).
- [ ] `OptRemapList.setRowById` (text lists, stage 4) and the message box's
  `getExtent`, `forceReflow`, `getPosition`, `resize` (control layout,
  stage 2) are still unknown commands here.

## Tests

`tests/engine_test.cpp` assembles each case by hand with
`tests/assembler.hpp` (opcode words and table entries written out, plus a DSO
v33 writer for the `exec` cases) and states the expected console lines,
values or files beside it. No original script, DSO or engine code is used.
`tests/input_test.cpp` compiles short scripts written for the test with
`../compiler` and feeds keys through `Engine::process_input`: bind make and
break, push and pop, the top map winning, releases after a pop, the global
map first, `bindCmd` with an empty make, the console dialog evaluating a
typed line, history, cursor keys, the remap control and the saved map,
dialog layers and focus, and the `MouseEnabled` export.

The `torque-engine` workflow builds and tests this on Linux (also under
address and undefined-behaviour sanitizers) and Windows.

## Next

- [x] Plug in the TorqueScript compiler (root `main.cs`, the prefs and key
  map files). `eval` and the F2 console use the same hook once the host sets it.
- [ ] Stage 2: drawing the canvas and controls from these objects (#248).
- [x] Stage 3: input through `ActionMap`, the console dialog, the remap
  dialog's `GuiInputCtrl`.
- [x] Stage 3 lab run against the original (above).
- [ ] Mouse clicks wait for stage 2's control layout.
- [ ] Compare the message formats and string-unit rules on the original.
