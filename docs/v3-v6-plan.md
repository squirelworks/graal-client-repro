# v3 to v6: where each client stands and how it gets finished

Refreshed 2026-11-16 from main after Quattro `#397` (`seteffect` merged) with
`#398` (`findplayer`) open beside it, and from the live epics
[#303](https://github.com/squirelworks/graal-client-repro/issues/303),
[#304](https://github.com/squirelworks/graal-client-repro/issues/304),
[#305](https://github.com/squirelworks/graal-client-repro/issues/305) and
[#373](https://github.com/squirelworks/graal-client-repro/issues/373). It
replaces nothing in those issues; it puts the four engine tracks in one
order with an owner for each piece. Older closed Torque / GS2 slice issues
are history only.

The short version: every folder from 3.04 to 6.x builds and logs in today.
The Pascal stand-ins still speak each build's tokens and packet ids. On
top of that, three shared engines now do real work on main:

| Engine | Builds | What the original is | What we build |
|---|---|---|---|
| **Torque (TGE 1.2)** | 3.04 Linux, 3.153 Mac (and the 3.0beta / 3.01 / 3.151 siblings) | One program: Torque's console runs the install's `.dso` menus; Graal's 2D game is one console class, `GuiGraalCtrl` | `common/torque/` (C++). Windowed `graal304-torque` boots the install, draws the menus and hosts the Pascal 2D game |
| **Split: Delphi launcher plus engine library** | 4.04r2, 4.11 Mac, 4.20r8, 5.00r7, 5.12 | A Delphi launcher owns the window and draws through 94 `graal_set` callbacks; `GraalEngine` keeps Torque's canvas and controls but no console, and runs the menus as compiled **GS2**; `Graal3DEngine` is a cut-down Torque world for 3D servers | Pascal launcher plus `common/cpp/graalengine` on the shared GS2 core |
| **Quattro (`quattro_lib`)** | 5.24r3 onwards, 5.30r3, 5.31r4, every 6.x | One native C++ program: GS2 controls named after Torque's, GS2 scripts for every shell dialog, OpenGL, no Torque left | `common/cpp/quattro` (`quattro-play`). 6.01r1 and 6.03r7 hand the Linux game to it |

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
| **3.04** Linux `G3D03014` | `graal304-torque` is the no-argument default; Pascal via `--pascal` / env. Boots the install's `main.cs`, draws the stock GUI, takes keys / F2, hosts the 2D game through `GuiGraalCtrl` (#255, #257, #259, #258). Player actions through `doA`/`doS`/`doD`/`doQ` (#358). Lab check of the windowed program is still open (#303) | TGE 1.2 program; menus are `.dso`; game is `GuiGraalCtrl` (31 methods) | Lab pass; UDP between players; Tutorial fidelity; side-by-side |
| **3.153** Mac PPC `G3D28015` | Same Torque default entry as 3.04; Pascal fallback; player actions on the Torque bridge (#358, #364) | Same engine as 3.04 on PowerPC: big-endian `.dso` float tables, the Mac script layout, four `GuiGraalCtrl` methods 3.04 lacks | 3.153 boot profile, PPC DSO variant and the four methods; 3D mode (protocol 19 on port + 1) later |
| **4.04r2** `G3D17026` | Pascal launcher plus `common/cpp/graalengine`: embedded GS2 menus, offline tutorial, weapon/item keys, built-in 2D actions (#264, #315, #360). Update packages after login still open (#304) | Delphi launcher plus `GraalEngine`; menus are 14 compiled GS2 scripts embedded in the exe | Update packages (`GRPKG001`), scripted server weapons, full 3D world |
| **4.11 Mac** `G3D27076` (first named 4.20r6) | Pascal stand-in; sibling of the engine-library line | Mac build of the 4.1x split | Same as 4.20r8, plus a Mac window |
| **4.20r8** `G3D20126` | Pascal stand-in / shell; built-in 2D actions (#360); C++ boot stub (`host4208`) is not the engine | Delphi launcher plus `GraalEngine.dll` and `Graal3DEngine.dll` | Engine-library session like 4.04r2; `GR-V1.05` board layers; 3D |
| **5.00r7** `G3D22067` | Pascal stand-in; Login-server mode reaches the server list; built-in 2D actions on the engine path (#360) | Same split; engine adds opcodes 48, 49, 54, 121 and `TGraalUniverse::runScripts` | Login server's scripted GUI (GS2), packages, base-file requests, 3D (protocol 24) |
| 5.12 `G3D14097` | Folder on the engine library (`--engine`): menus, login, level, walk, chat; Players window / tray from the lab log (#278, #317) | Same split | Options forms and remaining launcher callbacks; scripted Login GUI; 3D world draw |
| 5.24r3, 5.24r4 `G3D15010` | Folder `graal-5.24r4-G3D15010`: Pascal stand-in | First `quattro_lib` builds | Quattro program as the game (D3 / D5) |
| **5.31r4** `G3D26090` (and 5.30r3) | Scaffold: sends the token, no window, no session | `quattro_lib`, Torque control names and GUI field names still present | Everything: Quattro program on the GS2 core |
| **6.01r1** Linux `G3D0108A` | On Linux with an X display, the start screen hands the game to `quattro-play` (weapons, bombs/shots, hurt, Q list) (#359). Pascal fallback on Windows / no display / secure-login online | `quattro_lib` (Linux) | Windows/macOS Quattro windows; Login GUI (140, 197); remaining GS2 builtins; SEI00001 inside Quattro |
| **6.03r7** Linux `G3D0511C` | Same Quattro handoff as 6.01r1 (#359). Frame comparison work under #305. `seteffect` day/night tint (#397). `findplayer` in flight (#398) | `quattro_lib` (Linux) | Pixel fidelity; show-image animations; remaining corpus builtins; Windows folder on Quattro |
| **6.11r1** Mac, **6.1.1.3** `GNP1905C` | Connector login and a level; control names registered as stubs | `quattro_lib`, connector script (`StartScript_Connector`), `setprotocol` framer, AES/RC4 | GS2 machine to run the connector and shell scripts (D4); Quattro gameplay |
| 6.00b1, 6.00b2, 6.00r2, 6.00r4, Windows 6.03r7 `G3D0311C` | Folders exist as Pascal stand-ins | `quattro_lib` | Quattro program as the game (D5) |

Ato (the Seihai 3D client) already speaks Torque UDP protocol 24 against real
5.12 bytes and holds a link on Windows. That is a separate client in the
Seihai repo; its notes are the reference for the 4.x and 5.x 3D gate, not
code to copy here.

## Order of work

Each step is one properly sized PR. A step that needs the original program
checks against that build's own install, on the lab machines, and the install
stays out of the repository (it is loaded at run time, like the 3.04 `.dso`
files).

### Track A: Torque, 3.04 then 3.153 → #303

- [x] Boot the 3.04 scripts with objects and packages (#255)
- [x] GUI controls from the theme profiles (#257)
- [x] Keys through `ActionMap`, F2 console, remap (#259)
- [x] `GuiGraalCtrl` hosts the 2D game (#258)
- [x] Windowed `graal304-torque` (Linux X11, Windows GDI, macOS Cocoa)
- [x] `graal304-torque` is the no-argument release entry for 3.04 and 3.153
  (Pascal via `--pascal` / `GRAAL_PASCAL=1` / `GRAAL_PASCAL_GAME=1`)
- [ ] Debian lab check of that windowed program (#303)
- [ ] 3.153 boot profile: PPC `.dso` floats, its script layout, the four
  3.153 methods, compared with its own captures
- [ ] 3D mode: the Torque world (terrain, interiors, DTS) and protocol 19

### Track B: the GS2 core, shared by 4.x to 6.x (`common/cpp/gs2/`)

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
  commands they call; classes (`addClassScript`, `join`); run each one with
  no unknown opcode
- [x] **B4** GS2 controls drawn through the engine library's host calls
  (C1): `addcontrol` and the `GuiControl` tree from script, property set and
  methods, painter on the engine library's draw slots (#265, #268)
- [ ] **B5** `TShowImg` and the 2D game behind the playfield (Quattro already
  draws show-images on its canvas; engine-library depth still open)
- [x] **B6a** Script delivery: 131 to 134 and 193 into the machine
- [x] **B6b** (Quattro path) `GRESCR01` cache read/write (#260)
- [ ] **B6b** (remaining) `GRPKG001` packages, `GR-V1.05` layers on every
  consumer

### Track C: the 4.x and 5.0 split clients → #304

- [x] **C1** The engine library interface: the 94 `graal_set` callbacks,
  `renderGraalCanvas`, key forwarding, as a C ABI the Pascal launcher loads
  (#262)
- [x] **C2** 4.04r2 on it: the real launcher form, the embedded menus drawn
  through the callbacks, loopback login, level, walk, chat (#264, #275)
- [x] **C3** 5.12 folder on the engine library (#278); 4.20r8 and 5.00r7
  `--engine` handoff + loopback (same depth as 4.04r2 for the library
  path); 4.11 Mac still needs the same depth as 4.04r2
- [ ] **C4** 3D: library loads for `"3 "` servers (#294); draw the 3D world
  (shapes, Sun, Sky, camera) and prove protocol 21 / 24 on loopback

### Track D: the Quattro program (late 5 and 6.x) → #305 / #373

- [x] **D1** Program shell: window (X11 / Win32), software draw,
  `StartScript_*` host, `GuiGraalCtrl` playfield, show-images (#260, #378,
  #381)
- [x] **D2** 6.03r7 and 6.01r1 Linux hand off to `quattro-play` (#359)
- [x] **D2+** Selected GS2 weapon / world builtins: weapons, bombs/shots,
  hurt/Q list, floor items, spin, `showstats`, `noplayerkilling`,
  `testnpc`, `seteffect` (#397)
- [ ] **D2+** `#398` `findplayer(account)` (open PR); then the long-tail
  builtins (`putleaps`, `serverwarp`, …)
- [ ] **D3** 5.31r4 and 5.30r3 on Quattro
- [ ] **D4** 6.1.1.3 and 6.11r1: the connector script on the machine, the
  `setprotocol` framer, AES and RC4
- [ ] **D5** Quattro as the game for the Pascal-stand-in folders: 5.24r3/r4,
  6.00b1, 6.00b2, 6.00r2, 6.00r4, Windows 6.03r7

## Rules this plan keeps

- No original code, no decompile addresses or names, behaviour only from
  Graal_analysis.
- The Preagonal client and the open GS2 compiler are black-box references
  only: no code from either, and nothing transcribed from their sources. The
  Seihai opcode note was written from that compiler, so it is used for names
  only; behaviour comes from the Graal_analysis read of the real engines.
- Tests run against servers started on loopback. No lab machine names in the
  repository.
