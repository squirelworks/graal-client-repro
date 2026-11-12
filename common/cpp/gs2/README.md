# GS2 script machine (Tracks B1 to B4)

The script machine the 4.x, 5.x and 6.x clients share: the engines'
`TScriptExecutionSpace` running compiled GS2 on a `TGraalVar`. The 4.04r2 to
5.12 engine library and the late-5 and 6.x Quattro program both run their
menus and every server script on it. Plan: [docs/v3-v6-plan.md](../../../docs/v3-v6-plan.md),
step B1.

```
make -C common/cpp/gs2 test     # unit tests, GUI tests, gs2-dis, gs2-scan
```

Written from Graal_analysis `client-internals/gs2-vm-from-engines.md`,
`client-internals/showimg-particles-and-gs2-format.md`,
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

## GUI objects (B4)

`gui.cpp` is what the menus build and use; `gui_draw.cpp` draws it.

- **Objects.** `Screen::install` takes over `new` for `Gui*` classes,
  `ActionMap`, and the profiles made from another profile by name (`new
  GuiTextProfile("GuiSliderProfile")` copies `GuiTextProfile`'s fields,
  which is how the profiles script builds 111 profiles from a few). Each is
  a `Control`, and its properties are its child variables, as the
  scripts set them. The script that runs `new` handles the object's events:
  a button's press runs `GoButton.onAction` in that script.
- **Commands.** `addcontrol` adds the new control to the `with` object, or
  makes it a root outside one. `pushDialog` and `popDialog`, plus
  `cursorOn` and `cursorOff`. `makeFirstResponder`. The row commands on
  text lists, pop-up menus and tabs: `clearRows`, `addRow`, `setRowById`,
  `setSelectedRow`, `setSelectedById`, `getSelectedId`, `getSelected`,
  `getSelectedText`, `getSelectedRow`, `findText`, `findTextId`, `sort` and `rowCount`. The
  key map commands: `bind`, `unbind`, `getBinding`, `getCommand`, `push`
  and `pop`, with `GlobalActionMap` always active.
- **The screen.** One content and dialogs over it. Making a control the
  content, or pushing it, runs `onWake` down its tree; taking it away runs
  `onSleep`. Layout follows Torque's `horizSizing` and `vertSizing`
  against the parent's drawn size, as the 3.04 rebuild does
  (`common/torque/gui`).
- **Input.** A press goes to the topmost visible, active control. Buttons
  run `onAction`. Check boxes toggle `checked`, and radios with one
  `groupNum` are exclusive. Text edits take the focus. List rows and tabs
  run `onSelect(id, text)`, plus `onDblClick` on a double click. The
  focused text edit takes typing, backspace, delete, the arrows, home, end
  and return (`onAction`). Other keys go to the key maps: a bound script
  function gets 1 on press and 0 on release. A command that is no script
  function (`moveUp2D`, `doA`, `toggleConsole`) goes to the engine's
  `onEngineAction`.
- **Drawing** goes through a `Painter`: fills, text, and bitmaps by the
  name the script gives. The engine program supplies the painter: the
  4.x library on the launcher's draw slots, Quattro on its own renderer.
  Each control reads its profile, then `GuiDefaultProfile`. Themed buttons
  and text edits draw from the theme's cells, as in the 3.04 rebuild (nine
  per button state; eight for a text edit). Check boxes and radios use
  four cells. Text lists draw their columns; tabs are `tabwidth` wide.
  `GuiShowImgCtrl`, `GuiGraalCtrl` and `GuiGraal3DCtrl` go back to the
  engine (B5).

`gs2-scan --run --draw LIST --theme DIR` makes `MainMenuGui2D` the content
at 800 x 600 and writes every draw call to LIST. On the player's own 4.04r2
engine, with its `levels3d/gui` folder as the theme:

- the 14 menus run with every GUI command found;
- the screen holds 180 controls, 111 profiles and the global key map;
- the main menu lays out as its script places it (logo, nickname box,
  account and password boxes, the play-as radios, the save-password check
  box, and the Start, Become a Member, Options and Offline Test buttons).

The 5.12 engine's menus (profile 5.0) run the same way: 154 controls and
112 profiles, with every opcode they use. The one call still missing is the
engine's `Adventure_getInstallationPath`.

The only 4.04r2 commands still missing are the particle emitter's
`addglobalmodifier`, `addlocalmodifier` and `removemodifiers`, which belong
to `GuiShowImgCtrl` (B5). The menu background is a JPEG, which nothing
here reads yet.

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
- [x] `indexof` (82) and `format` (84), from Graal_analysis
  `client-internals/showimg-particles-and-gs2-format.md`. Readings: string
  search keeps letter case, `%d` truncates toward zero, `%f` defaults to six
  places
- [ ] `in` ranges and objects (80, 81), `type` (83),
  `log`, `getangle`, `getdir` (92, 95, 96), `indices`, `link`, the object
  compare (99, 100, 104), `substring`, `tokenize`, `translate`, `positions`
  (118, 120), multi-dimensional arrays and the array methods (133 to
  142), `foreach` (163)
- [ ] The built-in command table and its signature letters (B2)
- [x] Classes (`addClassScript`, packets 133 and 134) and `join`/`leave`:
  a joined class's functions and events are found after the object's own,
  and an object whose only code is a class gets `created`
- [ ] Whether the engines run a class's `onCreated` when an object that has
  its own joins it (here they do not), and the event masks OR-ed in
- [x] Script delivery (`delivery.cpp`): 131 to an object by id, 132 to a
  named object, 133 and 134 into classes, 193 from the weapon cache when its
  CRC32 matches
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
- [x] The GUI objects, their commands and input, and drawing through a
  painter (B4)
- [ ] Which object's script handles a control's events: here the script
  that ran `new`; the engines' lookup is not read
- [ ] `GuiTabCtrl.addRow` returns the tab as an object (the options
  window sets its `hint` inside `with`); other row lists return the index.
  What the engines return is not read
- [ ] `x`, `y`, `width` and `height` override `position` and `extent`
  when set (a few controls in the menus use them); the engines' link
  between the two is not read
- [ ] An inactive control (`active = false`) lets a press through to the
  control under it, so the main menu's show-images do not cover the
  Offline Test button; the engines' hit rule for show-images is only
  partly read
- [ ] Pop-up menus step to the next row on a press until the open list is
  drawn; window frames, scroll bars, sliders and multi-line text draw
  plainly (fill, frame, text), not from the theme
- [ ] The painter on the 4.x engine library's draw slots, and its key
  names (after #264), then `initialized`
- [ ] JPEG bitmaps (`graalv4screen.jpg`, the menu background)
- [ ] `ActionMap.save` and `load` (the key file), and mouse bindings
