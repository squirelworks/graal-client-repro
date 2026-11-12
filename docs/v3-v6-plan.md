# v3 to v6: where each client stands and how it gets finished

Written 2026-11-12 from main at #255, the open PRs #256 to #259, and the
Graal_analysis notes named below. It replaces nothing in
[#109](https://github.com/squirelworks/graal-client-repro/issues/109); it
puts that issue's gates, and the separate own-engine track, in one order with
an owner for each piece.

The short version: every folder from 3.04 to 6.x builds and logs in today,
but each one is the 2D Pascal client with that build's tokens and packet ids.
None of them runs the program the original ran. The originals fall into three
engines, and each engine is built once and shared:

| Engine | Builds | What the original is | What we build |
|---|---|---|---|
| **Torque (TGE 1.2)** | 3.04 Linux, 3.153 Mac | One program: Torque's console runs the install's `.dso` menus; Graal's 2D game is one console class, `GuiGraalCtrl` | `common/torque/` (C++), active |
| **Split: Delphi launcher plus engine library** | 4.04r2, 4.20r6 Mac, 4.20r8, 5.00r7, 5.12 | A Delphi launcher owns the window and draws through 94 `graal_set` callbacks; `GraalEngine` keeps Torque's canvas and controls but no console, and runs the menus as compiled **GS2** (`TScriptExecutionSpace`, `TGraalVar`, `TShowImg`, `TAdventure`); `Graal3DEngine` is a cut-down Torque world for 3D servers | Pascal launcher (the existing folders) plus the shared GS2 core below as the engine library |
| **Quattro (`quattro_lib`)** | 5.24r3 onwards, 5.30r3, 5.31r4, every 6.x | One native C++ program: GS2 controls named after Torque's, GS2 scripts for every shell dialog, OpenGL, no Torque left | One C++ program per build on the same GS2 core |

The piece the 4.x, 5.x and 6.x clients all share is the GS2 script machine
with its object model and its controls. Graal_analysis
`client-internals/gs2-vm-from-engines.md` shows the 4.2.0.8, 5.0.0.7 and
6.00 engines run the same machine with a few opcodes added per era. So the
"Quattro engine" is built bottom up, starting with that machine, and the 4.x
and 5.0 engine libraries are the same code with an older opcode profile.

## Audit, per version

"Repro today" is what the folder's program does on main. "Original" is the
Graal_analysis read of the real build. Open PRs are counted as not merged.

| Build | Repro today | Original | Missing |
|---|---|---|---|
| **3.04** Linux `G3D03014` | Pascal stand-in (start screen, list, login, level, walk, chat). Separately, `common/torque` boots the install's own `main.cs` and its 38 scripts and matches the original's console log and saved prefs (#255). GUI drawing (#257), keys and F2 console (#259) and `GuiGraalCtrl` hosting the 2D game (#258) are open. All of it runs only in the windowless lab tools. | TGE 1.2 program; menus are `.dso`; game is `GuiGraalCtrl` (31 methods) | A windowed `Graal304` built on the Torque engine that replaces the stand-in; UDP between players; the Tutorial level; side-by-side run |
| **3.153** Mac PPC `G3D28015` | Pascal stand-in with 3.04's login frame | Same engine as 3.04 on PowerPC: big-endian `.dso` float tables, the Mac script layout, four `GuiGraalCtrl` methods 3.04 lacks (`setNickName`, `setAccountName`, `setLanguage`, `retrieveAccountFields`) | Never tried on Torque. Needs a 3.153 boot profile, the PPC DSO variant and the four methods; 3D mode (protocol 19 on port + 1) is a later gate |
| **4.04r2** `G3D17026` | Pascal stand-in with the real start form and its resources | Delphi launcher plus `GraalEngine`; menus are 14 compiled GS2 scripts embedded in the exe (129 functions, 15,799 instructions on the Linux build; one tied to live loading) | GS2 machine, `TGraalVar` objects, the GS2 controls, `TShowImg`, the callback host, update packages (`GRPKG001`), 3D DLL |
| **4.20r6** Mac `G3D27076` | Pascal stand-in; no macOS window back end | Mac build of the 4.20 split | Same as 4.20r8, plus a Mac window |
| **4.20r8** `G3D20126` | Pascal stand-in, a Delphi shell that names the forms, and a C++ boot stub (`host4208`) that is not the engine | Delphi launcher plus `GraalEngine.dll` and `Graal3DEngine.dll` (`torque/4208-*.md`) | As 4.04r2; `GR-V1.05` board layers |
| **5.00r7** `G3D22067` | Pascal stand-in; Login-server mode reaches the server list | Same split; engine adds opcodes 48, 49, 54, 121 and `TGraalUniverse::runScripts` | The Login server's scripted GUI (GS2), `GR-V1.05`, `GRPKG001`, base-file requests, 3D (protocol 24) |
| 5.12 `G3D14097` | No folder | Same split | Folder, then as 5.00r7 |
| 5.24r3, 5.24r4 `G3D15010` | No folder | First `quattro_lib` builds | Folder on the Quattro program |
| **5.31r4** `G3D26090` (and 5.30r3) | Scaffold: sends the token, no window, no session | `quattro_lib`, Torque control names and GUI field names still present | Everything: Quattro program on the GS2 core |
| **6.01r1** Linux `G3D0108A` | Pascal stand-in | `quattro_lib` (Linux) | Quattro program; GS2 GUI from the Login server (140, 197); `GRESCR01` cache |
| **6.03r7** Linux `G3D0511C` | Pascal stand-in plus a `GRESCR01` header probe | `quattro_lib` (Linux) | As 6.01r1 |
| **6.11r1** Mac, **6.1.1.3** `GNP1905C` | Connector login and a level (#256 open for the Mac comparison) | `quattro_lib`, connector script (`StartScript_Connector`), `setprotocol` framer, AES/RC4 | GS2 machine to run the connector and shell scripts instead of the Pascal stand-ins |
| 6.00b1, 6.00b2, 6.00r2, 6.00r4, Windows 6.03r7 `G3D0311C` | No folder | `quattro_lib` (`client-internals/engine-600r2.md`, `engine-600r4.md`) | Folders on the Quattro program |

Ato (the Seihai 3D client) already speaks Torque UDP protocol 24 against real
5.12 bytes and holds a link on Windows. That is a separate client in the
Seihai repo; its notes are the reference for the 4.x and 5.x 3D gate, not
code to copy here.

## Order of work

Each step is one properly sized PR. A step that needs the original program
checks against that build's own install, on the lab machines, and the install
stays out of the repository (it is loaded at run time, like the 3.04 `.dso`
files).

### Track A: Torque, 3.04 then 3.153

Owned by the threads behind #257, #258 and #259 until those merge.

- [x] Boot the 3.04 scripts with objects and packages (#255)
- [ ] GUI controls from the theme profiles (#257)
- [ ] Keys through `ActionMap`, F2 console, remap (#259)
- [ ] `GuiGraalCtrl` hosts the 2D game (#258)
- [ ] A windowed `Graal304`: the canvas in a real window, the release
  program switched from the stand-in to the Torque engine
- [ ] 3.153 boot profile: PPC `.dso` floats, its script layout, the four
  3.153 methods, compared with its own captures
- [ ] 3D mode: the Torque world (terrain, interiors, DTS) and protocol 19

### Track B: the GS2 core, shared by 4.x to 6.x (`common/cpp/`)

- [x] **B1** Bytecode loader and machine (`common/cpp/gs2/`): the four
  segments, operands, the load-time pair fusions, value stack, calls and
  frames, events, sleep and `waitfor`, loop limit, per-engine opcode profiles
  (4.2, 5.0, 6.00). Synthetic tests; the 4.04r2 embedded corpus as an
  optional check when an install is present
- [x] **B2** Object model: `TGraalVar` properties, child variables and
  arrays, the universe, the `with` stack, `new` objects, registers, the
  command signature check, every opcode the 4.04r2 menus use
- [x] **B3** Embedded menus: find and load the `StartScript_*` bytecode from
  the player's own exe at run time, under their own names; the engine's
  commands they call (key modifiers, file and path helpers); classes
  (`addClassScript`, `join`); run each one with no unknown
  opcode; what is missing then is GUI (B4)
- [ ] **B4** GS2 controls drawn through the engine library's host calls
  (C1): `addcontrol` and the `GuiControl` tree from script, each class's
  property set and methods (`addRow` and the rest), `GuiShowImgCtrl`,
  `GuiGraalCtrl` as the playfield
- [ ] **B5** `TShowImg` and the 2D game behind the playfield, reusing the
  Pascal game library from #258
- [x] **B6a** Script delivery: 131 to 134 and 193 into the machine
- [ ] **B6b** The `GRESCR01` cache (Quattro thread, #260), `GRPKG001`
  packages, `GR-V1.05` layers

### Track C: the 4.x and 5.0 split clients

- [ ] **C1** The engine library interface: the 94 `graal_set` callbacks,
  `renderGraalCanvas`, key forwarding, as a C ABI the Pascal launcher loads
- [ ] **C2** 4.04r2 on it: the real launcher form, the embedded menus drawn
  through the callbacks, loopback login, level, walk, chat
- [ ] **C3** 4.20r8 and 4.20r6, then 5.00r7 (opcode profile 5.0, the Login
  server's GUI), then a 5.12 folder
- [ ] **C4** 3D: `Graal3DEngine` as a separate library, protocol 21 and 24

### Track D: the Quattro program (late 5 and 6.x)

- [ ] **D1** The program shell: window, OpenGL or software draw,
  `StartScript_GraalGui` and the shell scripts on the GS2 core
- [ ] **D2** 6.03r7 and 6.01r1 Linux on it, Login server GUI (140, 197)
- [ ] **D3** 5.31r4 and 5.30r3 on it
- [ ] **D4** 6.1.1.3 and 6.11r1: the connector script on the machine, the
  `setprotocol` framer, AES and RC4
- [ ] **D5** Folders for the builds with none: 5.12, 5.24r3/r4, 6.00b1,
  6.00b2, 6.00r2, 6.00r4, Windows 6.03r7

## Rules this plan keeps

- No original code, no decompile addresses or names, behaviour only from
  Graal_analysis.
- The Preagonal client and the open GS2 compiler are black-box references
  only: no code from either, and nothing transcribed from their sources. The
  Seihai opcode note was written from that compiler, so it is used for names
  only; behaviour comes from the Graal_analysis read of the real engines.
- Tests run against servers started on loopback. No lab machine names in the
  repository.
