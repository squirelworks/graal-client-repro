# Roadmap

Where graal-delphi stands and what comes next, as task lists: tick an item
in the PR that does it. Per-folder detail lives in each folder's README
("Not yet") and in the issues linked here. Updated 2026-11-16.

The Nov 2026 issue sweep closed the old per-slice trackers and folded their
open work into a short set of live epics. Closed issue numbers are not
relisted here; their checklists stay on the closed issues for history.
Only [#116](https://github.com/squirelworks/graal-client-repro/issues/116)
from that older set remains open (licence done; signing still on hold).

## Levels

- **0.0.1**: first rebuild. Logs in, walks, plays as far as its README says;
  not yet compared action by action with the original.
- **0.0.1.1**: a 0.0.1 rebuilt with a fix.
- **0.0.2**: checked side by side with the original client.
- **v0.0.3, v0.0.4**: combined releases of all 71 clients that existed
  then; each client's notes say what was matched and what was not.
- **v0.0.4.1**: development checkpoint for all 74 clients
  ([docs/releases/v0.0.4.1.md](docs/releases/v0.0.4.1.md)). Not a
  fidelity release.

v0.0.4 is the last published release ([RELEASES.md](RELEASES.md)). The
folders added after it (5.31r4, 6.1.1.3 and the seven Worlds builds) have
no release yet. v0.0.4.1 is being cut; the next release after it is 0.0.5.

## Done

- [x] Every client in a folder of its own (#56 to #90), plus 5.31r4 (#161),
  6.1.1.3 (#166), Worlds 614 (#158) and the six other Worlds builds: 80
  client folders
- [x] RELEASES.md, latest release per client (#96)
- [x] One-click release-all (#98) and the combined releases v0.0.3 and v0.0.4
- [x] Faithfulness pass from each real exe: #102 (1.21 to 1.41r1), #103
  (NewMain and 2.0 to 2.05), #104 (2.1 tests and NewWorld betas) closed;
  launcher, icon, game window and HUD work for every family (#118 to #141)
- [x] Torque language decided: C++ under `common/torque/` (#110)
- [x] C++ boot hosts for 3.04 and 4.20r8 (#162, #163), shared first-frame
  transport (#167), explicit script paths (#169)
- [x] Torque console: DSO v33 reader (#181), integer and branch VM subset
  (#182), native functions with checked argument counts (#183), instruction
  decoder (#184), bounded execution from serialized DSO files (#185);
  boot scripts with objects and packages (#255)
- [x] Torque GUI stock controls (#257), ActionMap / F2 console (#259), and
  `GuiGraalCtrl` hosting the 3.04 2D game in a windowed `graal304-torque`
  (#258)
- [x] CI builds only the legacy clients whose Pascal code changed (#170)
- [x] GS1 variable ownership made explicit for older Delphi (#171); 1st
  Graal collision probes (#168)
- [x] GS2 core B1–B3 and the GUI painter (B4 objects): loader, machine,
  embedded menus, controls (#261, #265)
- [x] Engine library C1/C2 and 5.12 on it (C3): slots, 4.04r2 menus and
  session, 5.12 folder (#262, #264, #278)
- [x] Quattro program shell on Linux for 6.01r1 and 6.03r7: session,
  `GRESCR01` cache, weapons, bombs/shots, hurt/Q list (#260, #359)
- [x] Quattro `seteffect(r, g, b, a)` day/night screen tint (#397, merged)

## Live epics

Open tracking issues only. Detail and checklists live on each issue.

- [ ] [#194](https://github.com/squirelworks/graal-client-repro/issues/194)
  focus versions
- [ ] [#373](https://github.com/squirelworks/graal-client-repro/issues/373)
  end-to-end playable focus versions through the lab stack (6.03r7 first)
- [ ] [#302](https://github.com/squirelworks/graal-client-repro/issues/302)
  classic clients (betas to 2.31, NewMain, NewWorld, GraalX, 39ster)
- [ ] [#303](https://github.com/squirelworks/graal-client-repro/issues/303)
  Torque 3.x (3.04, 3.153): lab check, fidelity, remaining engine gates
- [ ] [#304](https://github.com/squirelworks/graal-client-repro/issues/304)
  4.x / 5.x engine library and launchers, including 3D
- [ ] [#305](https://github.com/squirelworks/graal-client-repro/issues/305)
  Quattro (6.x and 5.24–5.31r4): fidelity, world objects and GS2
  - [x] #397 `seteffect` day/night tint (merged)
  - [ ] #398 `findplayer(account)` (open PR, in flight)
- [ ] [#306](https://github.com/squirelworks/graal-client-repro/issues/306)
  side builds (Java, Game Boy, Zelda Online, Graal3D 2000) and Seihai mode
- [ ] [#307](https://github.com/squirelworks/graal-client-repro/issues/307)
  releases, platforms and toolchains (stress gate, Delphi period build,
  macOS polishing)
- [ ] [#282](https://github.com/squirelworks/graal-client-repro/issues/282)
  v7 Worlds: from the C# stand-in to a working reproduction

## Release v0.0.4.1

- [x] release-all restores the Worlds player (the job's `VERSION` was read
  by MSBuild as the package version, runs 8 and 9 failed; #189)
- [ ] Run release-all for v0.0.4.1 and check the Linux and Windows results
  before publishing (Squirrel)

## Torque reconstruction (active → #303)

The 3.x to early-5 clients are Torque Game Engine 1.2-era programs. The
reconstruction is C++ under `common/torque/`; the historical v0 to v2
clients stay Object Pascal. Live tracking is
[#303](https://github.com/squirelworks/graal-client-repro/issues/303).

- [x] Per-build boot hosts, shared modules and first compiled-script /
  object slice (closed slice issues; see Done)
- [x] 3.04: stock GUI, ActionMap / F2, `GuiGraalCtrl` and windowed
  `graal304-torque` (#257, #259, #258)
- [x] 3.04 / 3.153: `graal304-torque` is the no-argument release entry
  (Pascal via `--pascal` / `GRAAL_PASCAL=1`)
- [ ] 3.04 Debian lab check of the windowed program (menu, keys, offline
  and online walk, clean exit); then 3.153 boot profile (PPC `.dso`
  floats, script layout, the four extra methods)
- [ ] 3D mode: the Torque world (terrain, interiors, DTS) and protocol 19

The late-5 and 6.x clients are not Torque (one `quattro_lib` program), so
they are a separate own-engine track under
[#305](https://github.com/squirelworks/graal-client-repro/issues/305).

## v3 to v6: the plan

[docs/v3-v6-plan.md](docs/v3-v6-plan.md) audits each 3.x to 6.x folder
against its original and orders the work in four tracks: Torque (3.04,
3.153), the shared GS2 core in `common/cpp/gs2/`, the 4.x and 5.0 split
clients, and the Quattro program for late 5 and 6.x.

- [x] B1: the GS2 bytecode loader and machine (`common/cpp/gs2/`)
- [x] B2: object creation, array literals, registers and the 5.0 and 6.00
  opcodes; the 4.04r2 menus run `created` with no refused opcode
- [x] B3: the menus embedded in the player's own exe found, named and run
- [x] B4: GUI controls and key maps those menus build; painter on the
  engine library's draw slots
- [ ] Remaining: B5 playfield / `TShowImg` depth, B6b packages and layers;
  C3 sibling platforms; C4 3D world; D3–D5 Quattro on the later builds
  (see the plan and #304 / #305)

## Builds with no folder

Real builds the research has read (Graal_analysis
`client-internals/build-catalogue.md`, `protocol/v5v6-windows-unpacked.md`,
`client-internals/version-tokens.md`) that have no folder here yet. Each
needs a folder named by the folder naming rule.

- [x] GraalX (`GNW23021`, a 2.01 build with the `.nw` reader; #175): `graal-x-GNW23021`
- [x] 5.12 Windows (`G3D14097`, Delphi launcher + engine): `graal-5.12-G3D14097`
- [x] 3.0beta, 3.01 and 3.151 Linux (`G3D16053`, `G3D27063`, `G3D27015`, tokens read from each `graalexe`): `graal-3.0beta-G3D16053`, `graal-3.01-G3D27063`, `graal-3.151-G3D27015`, each with its own game library on `graal304-torque`; 3.0beta and 3.01 log in as client type 4 on the gen-4 link
- [x] 4.03r1 Linux (`G3D11125`), 4.03r3 Windows (`G3D09125`), 4.11 Windows (`G3D26076`) and 4.20 Linux (`G3D22126`, r6 and r8): `graal-4.03r1-G3D11125`, `graal-4.03r3-G3D09125`, `graal-4.11-G3D26076`, `graal-4.20linux-G3D22126`, from the 4.20r8 rebuild
- [x] 4.20r6 Mac (`G3D21126`, the real Mac 4.20r6 of 2006-12-21, read from the binary): `graal-4.20r6-G3D21126`
- [x] 6.00 beta 1 Windows (`G3D03048`): `graal-6.00b1-G3D03048`
- [x] 6.00 beta 2 Windows (`G3D15010`, on the wire; same token as 5.24r3/r4): `graal-6.00b2-G3D15010`, from the 6.00 beta 1 rebuild
- [x] 5.24r3 and 5.24r4 Windows (`G3D15010`): `graal-5.24r4-G3D15010`
- [x] 6.00r2 and 6.00r4 Windows (`G3D26090`): `graal-6.00r4-G3D26090`
- [x] 6.03r7 Windows (`G3D0311C`): `graal-6.03r7win-G3D0311C`
- [x] The 39ster client, a Windows C++/SDL/OpenGL host (#176): `graal-39ster-1.00`, an offline build with no token, so the folder carries its version alone
- [x] 4.04r2 Mac (`G3D18026`, on the wire) and 4.04r2 Linux (`G3D19026`, on the wire): `graal-4.04r2mac-G3D18026`, `graal-4.04r2linux-G3D19026`, from the 4.11 Mac rebuild
- [x] 4.10r2 and 4.11 Linux (`G3D28076`, read from both binaries): `graal-4.11linux-G3D28076`, from the 4.11 Mac rebuild. The Mac 4.10r2 sends `G3D27076`, already `graal-4.11mac-G3D27076`
- [x] 5.12 Mac (`G3D15097`, on the wire): `graal-5.12mac-G3D15097`, from the Windows 5.12 rebuild
- [x] 6.004 Mac (`G3D27090`) and 6.015 Mac (`G3D3107A`), tokens read from each binary: `graal-6.004mac-G3D27090`, `graal-6.015mac-G3D3107A`
- [x] The later Graal3D beta (`GR3DV003`, read from the binary; Genesis3D): `graal-3d-20010523`
- [x] Inferred stand-ins, no binary held: 4.02.11 (`G3D28095`, public list only) as `graal-4.02.11-G3D28095`, and gs2lib's Graal Worlds token (`G3D2204D`) as `graal-worlds2013-G3D2204D`

5.30r3 shares the `graal-5.31r4-G3D26090` folder. 2.1.x, 2.2x before 2.22, 2.3
and 6.036 have tokens or version strings only, no exe, so they wait for
one. Android vx APKs have no folder yet (research only; not an open issue
here).

## 0.0.5

Per-client backlog and the live epics above. Tick folder README / release
notes items in the PR that does the fix.

- [ ] The `Not yet` list in each folder's `RELEASE_NOTES.md` and README:
  the per-client backlog (for example the NewWorld clock and sword,
  2.17.1's names, the Training view, the 2.22 gani frame rate)
- [ ] Classic fidelity and gameplay (#302)
- [ ] Torque 3.x lab and fidelity (#303)
- [ ] 4.x / 5.x engine library, launchers and 3D (#304)
- [ ] Quattro fidelity and GS2 builtins (#305), including #398
- [ ] Side builds and Seihai extras (#306)
- [ ] Release / platform gates (#307)
- [ ] Focus versions end to end (#373 / #194)

During each folder's PR, also tick or remove items in that folder's
README "Not yet" list that are already done (the lists were turned into
task lists mechanically on 2026-11-05 and some are older than the code).

## Seihai and later

Tracked under
[#306](https://github.com/squirelworks/graal-client-repro/issues/306).
Secure login (`SEI00001`) is in for the server-capable rebuilds that the
issue marks done; remaining gaps stay there.

- [x] `common/GSecCrypto.pas` and `common/GSecLogin.pas` (pure Pascal,
  RFC vectors), pins, `off`/`auto`/`required` (off by default)
- [x] Gen 5 Delphi, gen 3/2 game links, and the listed 3.x–6.x folders
  (see #306)
- [ ] 5.31r4: its folder is a scaffold that speaks to no server yet, so
  the login goes in when its link does
- [ ] Gen 3 and gen 2 list link: it sends id 0 `newmain` with no key or
  token, so the spec's list C1 does not fit it (open question on #306)
- [ ] seihai-gserver-v2 side (its own repo)
- [ ] Mixed-build stress and Seihai extras mode (#306)

## On hold

- [ ] [#116](https://github.com/squirelworks/graal-client-repro/issues/116)
  licence and code signing (licence: Apache-2.0 via #357; signing route
  still the owner's call)

## Standing goals

- [ ] Phase 4 for every build: headless mode, fuzzed receive path, leak
  checks, and a place in the Seihai 1000-player stress runs. The 2.0 to
  2.05 folders and 2.22 have a "Stress runs (phase 4)" section; 2.17.1
  carries 2.05's; the rest pass `scripts/stress.sh` only
- [ ] Phase 5 kept current: every merged fix gets a release-notes line
  and goes out with the next combined release
