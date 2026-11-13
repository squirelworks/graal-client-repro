# Roadmap

Where graal-delphi stands and what comes next, as task lists: tick an item
in the PR that does it. Per-folder detail lives in each folder's README
("Not yet") and in the issues linked here. Updated 2026-11-11.

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
  decoder (#184), bounded execution from serialized DSO files (#185)
- [x] CI builds only the legacy clients whose Pascal code changed (#170)
- [x] GS1 variable ownership made explicit for older Delphi (#171); 1st
  Graal collision probes (#168)

## Release v0.0.4.1

- [x] release-all restores the Worlds player (the job's `VERSION` was read
  by MSBuild as the package version, runs 8 and 9 failed; #189)
- [ ] Run release-all for v0.0.4.1 and check the Linux and Windows results
  before publishing (Squirrel)

## Torque reconstruction (active)

The 3.x to early-5 clients are Torque Game Engine 1.2-era programs. The
reconstruction is C++ under `common/torque/`; the historical v0 to v2
clients stay Object Pascal. Parent issue
[#109](https://github.com/squirelworks/graal-client-repro/issues/109)
holds the ordered gates.

- [ ] #151 per-build boot, DSO execution, object and host-entry contracts
- [ ] #152 shared modules and explicit per-program build manifests
- [ ] #172 first compiled-script execution and object slice, compared with
  the original
- [ ] 3.04: the shipped entry sequence and DSO set, then GUI, input and the
  Graal game control (loopback login, level, movement)
- [ ] 3.153, then Windows 4.04r2, 4.20 and early 5 from each build's own
  evidence
- [ ] #110 finish: record provenance for any outside engine material
- [ ] #154 7.x Worlds: optional research only

The late-5 and 6.x clients are not Torque (one `quattro_lib` program), so
they are a separate own-engine track (#109, "Separate own-engine track").

## v3 to v6: the plan

[docs/v3-v6-plan.md](docs/v3-v6-plan.md) audits each 3.x to 6.x folder
against its original and orders the work in four tracks: Torque (3.04,
3.153), the shared GS2 core in `common/cpp/gs2/`, the 4.x and 5.0 split
clients, and the Quattro program for late 5 and 6.x.

- [x] B1: the GS2 bytecode loader and machine (`common/cpp/gs2/`)
- [x] B2: object creation, array literals, registers and the 5.0 and 6.00
  opcodes; the 4.04r2 menus run `created` with no refused opcode
- [x] B3: the menus embedded in the player's own exe found, named and run
- [ ] B4: the GUI controls and key maps those menus build

## Builds with no folder

Real builds the research has read (Graal_analysis
`client-internals/build-catalogue.md`, `protocol/v5v6-windows-unpacked.md`,
`client-internals/version-tokens.md`) that have no folder here yet. Each
needs a folder named by the folder naming rule.

- [x] GraalX (`GNW23021`, a 2.01 build with the `.nw` reader; #175): `graal-x-GNW23021`
- [x] 5.12 Windows (`G3D14097`, Delphi launcher + engine): `graal-5.12-G3D14097`
- [ ] 6.00 beta 1 Windows (`G3D03048`)
- [ ] 6.00 beta 2 Windows (`G3D15010`)
- [x] 5.24r3 and 5.24r4 Windows (`G3D15010`): `graal-5.24r4-G3D15010`
- [x] 6.00r2 and 6.00r4 Windows (`G3D26090`): `graal-6.00r4-G3D26090`
- [x] 6.03r7 Windows (`G3D0311C`; the folder here is the Linux build): `graal-6.03r7win-G3D0311C`
- [ ] Android vx: seven APK builds, Classic 1.7 and 1.8 among them (#177)
- [x] The 39ster client, a Windows C++/SDL/OpenGL host (#176): `graal-39ster-1.00`, an offline build with no token, so the folder carries its version alone

5.30r3 shares the `graal-5.31r4-G3D26090` folder. 2.1.x, 2.2x before 2.22, 2.3
and 6.036 have tokens or version strings only, no exe, so they wait for
one.

## 0.0.5

- [ ] The `Not yet` list in each folder's `RELEASE_NOTES.md` and README:
  the per-client backlog (for example the NewWorld clock and sword,
  2.17.1's names, the Training view, the 2.22 gani frame rate)
- [ ] #100 precursors and side builds: remaining folders
- [ ] #101 1998 betas to 1.1: remaining folders
- [ ] #105 2.17.1 to 2.31: remaining folders
- [ ] #106 3.x to 6.x: look pass for the remaining folders
- [ ] #108 2.22: the rest of the real client
- [ ] #174 v0 to v2 gameplay: exact-build movement, GS1, weapons, NewWorld
- [ ] #179 1.35: the one-byte remote-player prefix
- [ ] #180 2.05r2: keep terminal LF bytes inside counted raw messages
- [ ] #107 stress gate: first run on Actions
- [ ] macOS: framework path in `scripts/release/darwin-cross.sh` so the
  Cocoa window links (notes in project files, `graal-delphi/macos-cross/`),
  then run it on a real Mac (#115)
- [ ] #114 a real Delphi 5 or 7 build

During each folder's PR, also tick or remove items in that folder's
README "Not yet" list that are already done (the lists were turned into
task lists mechanically on 2026-11-05 and some are older than the code).

## Seihai and later

- [ ] #173 GS2: serialized scripts, envelopes, cache and event delivery
- [ ] #150 Seihai mode: extras only when the server is Seihai
- [ ] #148 encrypted login channel for the server-capable rebuilds, original
  login kept as the fallback (#153 closed as its duplicate)
- [ ] #149 mixed-build stress in one level on seihai-gserver
- [ ] #178 implementation roadmap: v0 to v2 and vx, verified completion

## On hold

- [ ] #111 2.3 from a real 2.3 exe (the supplied "2.3" archive turned out
  to hold the 2.31 exe)
- [ ] #112 Graal3D side by side (d3drm.dll)
- [ ] #113 4.04r2 side by side (the real client crashes)
- [ ] #116 licence and code signing (Squirrel decides)

## Standing goals

- [ ] Phase 4 for every build: headless mode, fuzzed receive path, leak
  checks, and a place in the Seihai 1000-player stress runs. The 2.0 to
  2.05 folders and 2.22 have a "Stress runs (phase 4)" section; 2.17.1
  carries 2.05's; the rest pass `scripts/stress.sh` only
- [ ] Phase 5 kept current: every merged fix gets a release-notes line
  and goes out with the next combined release
