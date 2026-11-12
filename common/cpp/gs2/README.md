# GS2 script machine (Tracks B1 to B3)

The script machine the 4.x, 5.x and 6.x clients share: the engines'
`TScriptExecutionSpace` running compiled GS2 on a `TGraalVar`. The 4.04r2 to
5.12 engine library and the late-5 and 6.x Quattro program both run their
menus and every server script on it. Plan: [docs/v3-v6-plan.md](../../../docs/v3-v6-plan.md),
step B1.

```
make -C common/cpp/gs2 test     # unit tests, gs2-dis, gs2-scan
```

Written from Graal_analysis `client-internals/gs2-vm-from-engines.md`,
`protocol/gs2-client-vm.md` and `protocol/gs2-client-only-opcodes.md` (the
static reads of the 4.2.0.8, 5.0.0.7 and 6.00 engines). Where those notes
give the stack shape of an opcode only by name (object creation, array
literals, `substring`, `foreach`), the shape was taken from the compiled
menus inside the player's own 4.04r2 engine, which the machine then has to
run. Opcode names follow
the Seihai opcode note, names only. No code from the open GS2 compiler or from
Preagonal.

## What it does

- **Loader** (`loader.cpp`): the four big-endian segments (event mask,
  function table with the `public.` prefix, string table, code), the `F0`
  to `F6` operand markers, and the load-time pair fusions into opcodes 200
  to 233, plus 234 to 240 and 242 on 6.00. A segment type outside 1 to 4 or a truncated header ends the read,
  as in the engines; a string index outside the table is refused.
- **Profiles**: the 4.2 set (154 opcodes), 5.0 (adds 48, 49, 54, 121) and
  6.00 (adds 54, 121, 234 to 242). An opcode outside the script's profile
  stops it with `unknown opcode N for engine X`.
- **Objects** (`var.cpp`): a `Var` has its own value (number, string, object
  link or array) and named children, looked up case-insensitively.
- **Machine** (`machine.cpp`): value stack capped at 10000; calls into the
  script's own functions, another object's script, or a registered command
  (signature length is the minimum argument count; `adventure.` commands
  only from a variable whose name starts with `login`); parameters bound by
  opcode 51; return into the caller's slot; `Callstack overrun` past 9999
  frames; the name search (`with` objects, the frame, `thiso`, the level,
  the universe, then `playero`) and the reserved names; registers 0 to 1023
  (`setreg`, `getreg`, `makeprop`, and their folds); `new T(name)` through
  an object factory, with commands found by object, by the object's class
  (`GuiTextListCtrl.addRow`) or by name; array literals; `makeoldscriptvar`;
  `foreach`; `substring`; `translate`; the engines' three-way compare
  (numbers within 0.0001 are equal, strings compare without case); 5.0's 48,
  49 and 121; the loop limit (the 10001st check stops the script); events queued
  per object (`created`, `initialized`, scheduled and cancelled names), at
  most 9999 queued; `sleep` on the 2D clock (0.05 a pass) with a timeout due
  below 0.0001; the error recorder (`GraalScript: ... in script of NAME`, at
  most 20 distinct texts).

## Start scripts and engine commands (B3)

- `startscripts.cpp` finds every zlib stream in the player's own engine
  file that inflates to a script, names each `StartScript_*` stream by a
  function only that script defines (the key maps by the `ActionMap` they
  build), and attaches them to universe variables of those names in file
  order. The names are the ones the engines carry; the attach order is not
  read.
- `engine_commands.cpp` adds the engine's non-GUI commands the menus call:
  `setTimer` (one `timeout` event), `catchevent` (the caught object's event
  queues the catcher's function), `extractFileBase`, `extractFilePath`,
  `lowercase`, and, when the engine program supplies them, `echo`,
  `openURL`, `keydown`, `getResolutionList` and the `Adventure_*` calls.
  A hook left empty leaves the command unregistered, so a script gets the
  engines' "not found" error rather than a silent success.

## Checked against the original

`gs2-scan` finds the compiled scripts a program carries as zlib streams and
loads them; `--run` attaches each to a variable on one machine and runs
`created`. On the player's own 4.04r2 `GraalEngine.dll` (not in this
repository) it finds 14 scripts with 129 functions and 15,799 instructions,
the counts Graal_analysis `client-internals/linux-404r2-embedded-scripts.md`
records for that corpus. A 5.12 install's engine DLL gives 18 scripts, 116
functions and 15,008 instructions, all readable.

`gs2-scan` names all 14 4.04r2 streams (Profiles, MainMenu, GraalGui,
OptionsWindow, PlayerProfile, LoadLevelGui, MoveMap2D, MoveMap3D,
QuitDialog, GraalGui3D, LoadingGui3D, MessageBoxDialog, SetupDialog,
SelectFileDialog) and the 11 start scripts among the 5.12 streams; the other
seven 5.12 streams are weapon scripts (`onWeaponFired`).

With `--run`, all 14 4.04r2 scripts run `created` with no refused opcode:
11,289 instructions, 291 objects made. What is left is what the engine
provides, not the machine: the GUI commands (`addcontrol`, the text list's
`addRow`, `clearRows`, `setSelectedRow`) and the key modifiers
(`addglobalmodifier` and the rest), steps B3 and B4. The 5.12 scripts add
`format` (84), `objindex` (82) and a few engine functions
(`Adventure_getInstallationPath`, `extractFileBase`, `lowercase`).

## Not yet

Each is refused with `opcode N (name) is not implemented` instead of
guessed.

- [x] Object creation and array literals (37, 40, 42, 43), registers and
  `makeprop` (45 to 47), 48, 49, 121, and the 6.00 folds 234 to 240 and 242
- [ ] 41 (`makevar`), 38 and 39 (`initarray`, `setarray`), 54, 104
  (`compare`, whose result slot the read leaves unclear) and fold 241 (which
  objects carry its flag is not read)
- [ ] An opcode with no case: the engines skip two slots after a helper;
  here it stops the script
- [ ] `waitfor` (11): it pops a number and two strings and registers a
  catch; how the resumed script sees the result is not read
- [ ] `in` ranges and objects (80, 81), `index`, `type`, `format` (82 to 84),
  `log`, `getangle`, `getdir` (92, 95, 96), `indices`, `link`, the object
  compare (99, 100, 104), `substring`, `tokenize`, `translate`, `positions`
  (118, 120), multi-dimensional arrays and the array methods (133 to
  142), `foreach` (163)
- [ ] The built-in command table and its signature letters (B2)
- [ ] Joined classes: the instruction walk across a class's code, and the
  event masks OR-ed in
- [ ] The second event-mask word and `needEvent`
- [ ] What an event runs: here `created` runs the script's `onCreated`; the
  read names the queued event but not the lookup
- [ ] Number to text: `%.15g` here; the engines' format is not read
- [ ] `new T(name)` stores the object in the universe member `name`
  (opcode 40, whose client name is `setmember`); a command named without an
  object runs on the newest `with` object (the menus call `addcontrol`
  inside `with (parent)`)
- [ ] `null` pushes an empty string; `this` is the newest `with` object or
  `thiso`; plain divide by zero gives 0 like the fused divide; a plain object
  made by `new` takes every property name until its class (B4) gives the
  real list; 49's array takes the slot of the last number it read. Each is
  a reading, not an observed result
- [ ] `vecx`/`vecy` use the GS1 direction table (up, left, down, right);
  the engines' four entries are not read
- [x] The 4.04r2 menus found and named in the engine file, and the
  engine's non-GUI commands (B3)
- [ ] `extractFileBase` drops the extension: read from how the options menu
  cuts language names, not from the engine
- [ ] `catchevent` queues the catcher's function with the caught event's
  arguments; what the engines pass is not read
- [ ] The GUI commands (`addcontrol`, `pushDialog`, the text list's rows,
  `ActionMap` binds and modifiers) on the Torque GUI layer (B4), then
  `initialized`
