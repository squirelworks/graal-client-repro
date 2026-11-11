# Handoff to Cursor (from 2026-11-07)

Read this first. It says what graal-delphi is, how the work here is run, what
changed in the last days, what is on hold and why, where everything lives,
and which decisions are still open. The rules are short and binding; they
are also in [AGENTS.md](AGENTS.md) and `.cursor/rules/graal-delphi.mdc`, so
Cursor applies them on every request.

State as of 2026-11-11. **v0.0.4 is the last published release** (71
clients). Since then three folders were added (74 now), the Torque
reconstruction restarted in C++ (#109, #110), and v0.0.4.1, a development
checkpoint, is being cut (section 4). Sections 5 and 6 keep the
2026-11-05 handoff text where it still holds; where it and a later
section disagree, the later state wins.

Owner: Squirrel (GitHub `squirelworks`).

## 1. What the project is

Two public repos, worked on together:

| Repo | What it is |
|---|---|
| [graal-client-repro](https://github.com/squirelworks/graal-client-repro) (this repo, formerly graal-delphi) | Faithful rebuilds of every classic Graal Online client, one folder per build, in Delphi (Object Pascal), built with Free Pascal 3.2 in Delphi mode. 74 client folders: 70 Graal builds from the 1998 betas to Worlds 6.114, plus Java (Zelda Online 1 and 2, Java Graal) and the Game Boy Color demo. 3.04 and 4.20r8 also carry C++ boot hosts; Worlds 6.114 is a portable C# stand-in. |
| [Graal_analysis](https://github.com/squirelworks/Graal_analysis) | The research the rebuilds are written from: wire protocol, file formats, per-version client behaviour, lab notes, and the Graal Technical Reference Manual (TRM, `manual/`, published 0.0.3 and 0.0.4). It has its own `AGENTS.md`, `.cursor/rules/graal-analysis.mdc` and ordered task list `docs/NEXT.md`. |

Related, not covered here: the Seihai stack (`seihai` client, `seihai-gserver`,
`seihai-listserver`, `seihai-rc`, `seihai-npcserver`, `seihai-servertools`,
and the GPL forks `seihai-gserver-v2`, `seihai-gs2lib`). CI here logs every
rebuild into `seihai-gserver`, and the stress gate runs against it. The
Seihai stack has its own Cursor handoff from 2026-10-31 (in the tarball
under `project-files/handoff/cursor/`, and in project files at
`handoff/cursor/`).

The goal of each folder: behave like the original on the wire and on
screen, then get hardened so it can run in large stress runs. The phases
are in the README (Wire, World, Play, Harden and stress, Release).

## 2. Rules (binding)

- **No original Graal code in the repo.** Game data (tiles, ganis,
  heads, bodies, levels) is loaded at run time from an install the player
  supplies (`graal-assets/`, see [docs/assets.md](docs/assets.md)). By
  Squirrel's decision (D4), everything embedded in each real exe (icons,
  cursors, bitmaps, dialogs and forms, menus, string tables, version info,
  manifest, fonts, sounds) is extracted per version and wired into that
  folder's rebuild.
- **No raw decompile material.** No code or data addresses, RVAs or file
  offsets, no Ghidra/IDA names (`FUN_`, `DAT_`, `LAB_`), no decompiled C,
  in source, comments, commit messages or PR text. Findings come from
  Graal_analysis as plain behaviour. Raw decompiles stay with Squirrel.
- **No real servers.** Test only against servers you start yourself on
  loopback (seihai-gserver, `scripts/relay98.py`), in a container or CI.
- **One change per branch and PR.** A folder PR touches only its folder
  (plus `common/` when a shared unit really changes). **Folder PRs do not
  touch the root `README.md`.** Root docs change in their own PR.
- **PR attribution.** Every PR body starts with the two-line attribution
  block the project uses:

  ```
  <!-- claude-projects-attribution: {"github_login":"squirelworks"} -->
  _Requested by **Squirrel** · [project thread](<link to the thread or task>)_
  ```

  Cursor PRs keep the marker line and credit Squirrel the same way.
- **Merging.** Agents open PRs; a merger (Squirrel or the merger session)
  checks folder scope, no root README changes, the attribution block and
  no raw addresses, then merges when CI is green. Do not merge your own PR.
- **Releases.** No tags or releases by hand. Every release is **one
  combined version for every client**, made in one action by Squirrel
  (see section 4). No per-folder releases or tags.
- **Each folder its own resources.** Every folder is matched against its
  own real client, never another version's (2.22's set is for 2.22 only;
  the 2.05-derived copies do not stand in for a later version). Folders
  with no real exe are modelled on the nearest real sibling on each side
  plus the Graal_analysis version profiles, and their notes say which.
- **Squirrel's PC is for real clients only.** It runs the real clients
  for side-by-side captures and the final check on real Windows. Building,
  tests, stress runs and screenshot diffs run in CI or cloud machines.
  Never leave error dialogs open on that screen.
- **Checkmarks.** Every incremental fix list is a GitHub task list
  (`- [ ]` / `- [x]`): folder READMEs' "Not yet" sections, `ROADMAP.md`,
  issue bodies. Tick an item in the same PR that does it.

## 3. Repo layout

```
common/            units shared by every build (only when byte-for-byte the same behaviour)
graal-<ver>-<token>/   one folder per build: src/, tests/, README.md, RELEASE_NOTES.md
javagraal-2000/  zelda-online1-Z3V102/  zelda-online2-Z3V103/   Java clients
graalgb-1.10/      Game Boy Color demo
common/torque/     the Torque reconstruction in C++ (console: DSO reader, decoder, bounded VM; host304, host4208 boot hosts) plus the parked Pascal VM
scripts/           build.sh, test.sh, loopback.sh, relay98.py, stress.sh, release/ (incl. darwin-cross.sh), win/, assets/, builtin/
docs/assets.md     the graal-assets/ folder, search order per build
.github/workflows/ ci.yml (Linux, Windows, loopback), release.yml (one folder),
                   release-all.yml (all clients), per-client workflows for Java/GB/3D
RELEASES.md        one row per client: its latest release
ROADMAP.md         project-level checklist and where each client stands
```

Folder naming: `graal-<version>-<token>`, the token exactly as the build
sends it on the wire (README, "Folder naming rule").

Build and test (Linux): `sudo apt-get install fp-compiler fp-units-base fp-units-fcl libx11-dev`,
then `scripts/build.sh` and `scripts/test.sh`. Tests run with range and
overflow checks and the heap tracer and must end with no unfreed memory.
A new folder needs `python3 scripts/win/make_winres.py` or CI fails.

## 4. Release flow

- **One combined release for every client.** Actions → **release-all** →
  Run workflow with the version (`v0.0.4` was the last published one;
  `v0.0.4.1` is next, notes in `docs/releases/v0.0.4.1.md`). Runs 6, 8
  and 9 failed at the Worlds player restore: the job's `VERSION` reached
  MSBuild as the package version. The fix keeps it out of `dotnet`. It (1) checks
  every `RELEASE_NOTES.md` mentions the version, (2) builds and tests every
  client and stamps the version into each exe, (3) runs the **stress
  gate**, `scripts/stress.sh` per Delphi client against a local
  seihai-gserver (soak with walkers crossing a level link, connect and
  disconnect churn with killed sessions, 80 scripted NPCs, memory growth
  check; relay builds against `relay98.py`; Graal3D offline), (4) publishes
  the zips (Linux and Windows; Java and Game Boy through their own
  workflows; macOS best effort, never blocking), and (5) updates
  `RELEASES.md`. `stress_gate = report` releases even if a client fails;
  `publish = no` makes drafts. `release.yml` still builds one folder.
- **The stress job was skipped in the v0.0.4 run** (Actions run
  42000323978), so the gate has never run on Actions: [#107](https://github.com/squirelworks/graal-client-repro/issues/107).
- **macOS zips: none in v0.0.4.** Every client failed to link on the macOS
  cross build: the new Cocoa window (#140) needs Apple frameworks, and
  `scripts/release/darwin-cross.sh` extracts only `usr/lib` from the SDK.
  The untested two-line fix is in `project-files/graal-delphi/macos-cross/0.0.4-link-failure-notes.md`;
  the toolchain setup script is `setup-darwin-cross.sh` next to it. The SDK
  and `errore.msg` downloads are already pinned by sha256 (#144); keep any
  new download pinned the same way. The Cocoa window is link-tested only and
  has never run on a Mac ([#115](https://github.com/squirelworks/graal-client-repro/issues/115)).
- **RELEASES.md** lists only the **latest** release per client, one row
  each, with a link to the releases page for history (Squirrel's rule).
- Each folder's changes go as bullets under `## What's new in v0.0.5` (add
  the heading) in its `RELEASE_NOTES.md`. Anything that can't be fixed
  stays under `Not yet` as a known limitation; it does not block a release.

## 5. What changed

### 2026-11-06 to 11-11

- **Three new folders**: 5.31r4 scaffold (#161), 6.1.1.3 running to the
  clear hello (#166), and a portable C# stand-in for Worlds 6.114 (#158).
  74 client folders. RELEASES.md lists them as not released yet.
- **Torque restarted, in C++** (Squirrel, #110): boot hosts for 3.04 and
  4.20r8 (#162, #163), shared first-frame transport (#167), explicit
  script paths (#169), and the console: DSO v33 reader (#181), integer and
  branch VM subset (#182), native functions (#183), instruction decoder
  (#184), bounded execution from serialized DSO (#185). Gates in #109.
- **Corrections**: the 3.04 name table and the 6.037 checklist are not a
  host (#164); a minimal GRESCR01 buffer is accepted, not a script VM (#165).
- **Legacy clients**: 1st Graal collision probes (#168), GS1 variable
  ownership for older Delphi (#171), CI builds only the changed Pascal
  clients (#170).
- **Release**: v0.0.4.1 workflow and notes (#186 to #188).
- **New issues**: per-family roadmaps #172 to #178 (TGE slice, GS2, v0 to
  v2 gameplay, GraalX, 39ster, Android vx, overall plan), client fixes
  #179 and #180, Seihai ideas #148 to #150 (#153 closed as a duplicate), #151 and #152
  (per-build contracts and manifests), #154 (Worlds research, optional).
- **Launchers, per build** (#110 retired the blanket claim): the Delphi
  launcher plus C++ engine DLL is the 4.04r2 to 5.12 split. From 6.00
  beta 1 and 5.24r3 (2010) on, Windows ships one `quattro_lib` exe; the
  Linux 6.01r1 and 6.03r7 are one native C++ program; Worlds is a Unity
  player. None of the 6.x or Worlds builds has a Delphi launcher.

### 2026-11-04 to 11-05

- **Every client has a folder of its own** (#56 to #90), from the 1998
  betas to 6.03r7, the Java clients and the Game Boy demo.
- **v0.0.3, then v0.0.4, released for all 71 clients at once** (#98,
  #130, #132 to #135). RELEASES.md (#96) shows every client at v0.0.4.
- **Faithfulness pass, per family, from each client's own real exe**:
  the start dialog or launcher, icon, game window size, HUD and fonts,
  resources compiled in: 1998 betas (#124, #129), 1.x (#127, #128, #137),
  2.0x (#121), 2.1 to 2.21 (#126, #138), 2.22 (#97, #131, #136), 2.31 and
  the 2.3 stand-in (#118, #119, #141), Graal3D (#120), 4.04r2 (#123), every
  client's own icon (#122). Issues #102, #103 and #104 are closed; #100,
  #101, #105 and #106 carry their remaining folders to 0.0.5.
- **Window flow rule** (Squirrel): the real launcher *is* the start
  screen, its own small form sized to the art, with only the buttons the
  real one has; then the server list window; only then the game window at
  its real size.
- **CI**: a pull request builds and tests only the client folders it
  touches (#125).
- **macOS**: a Cocoa window back end (#140) and macOS zips in release-all
  (#139); the cross link fails (section 4).
- **Torque**: the parked stage 1 script VM is on main in `common/torque/`
  and compiles under FPC (#145); nothing uses it (section 6).
- **Docs**: machine-specific details removed (#146).
- **Graal_analysis**: TRM 0.0.3 and 0.0.4 published; the Torque study
  (#242) and its stage checklist (#250) merged; the facts the v0.0.4
  rebuilds traced from the real clients written up (#249).
- **Seihai stack**: seihai #369 (HUD fonts and per-version UI facts from
  graal-delphi v0.0.4) and #370 (machine details removed); seihai-gserver
  stage 3.1 to 3.5 (#37 to #41: level NPCs, baddies with a level leader,
  bombs and shots, player hits and kill claims, a lab run with real clients).

## 6. On hold, and why

Torque is no longer on hold: the 2026-11-05 hold was lifted by the C++
decision (#110) and the work is active under #109 (section 5).

| Item | Why | Issue |
|---|---|---|
| 2.3 as its own client | No distinct 2.3 exe has been verified; the folder is the 2.31 rebuild with 2.3's token. #94 (remove it) closed, so it stays. The archive labelled 2.3 holds an exe byte-identical to the 2.31 one (version 2.3.1.0; #111, 2026-11-09), so it does not settle this. | [#111](https://github.com/squirelworks/graal-client-repro/issues/111) |
| Graal3D side by side | The real client needs `d3drm.dll`, which modern Windows lacks; none on the PC, not downloaded from unknown sites. | [#112](https://github.com/squirelworks/graal-client-repro/issues/112) |
| 4.04r2 side by side | The real client crashes on start (access violation; its folder holds only the exe). | [#113](https://github.com/squirelworks/graal-client-repro/issues/113) |
| Code signing, licence | Owner decisions. | [#116](https://github.com/squirelworks/graal-client-repro/issues/116) |
| Graal_analysis items | pyReborn files (#244), 2.1 to 2.16 builds (#245), 1.32 export (#246), 5.x/6.x Login capture (#247). | Graal_analysis |

## 7. Open PRs

As of 2026-11-11: #189 (release-all restore fix and this docs refresh).
Check GitHub for the current list before starting.

## 8. 0.0.5: the backlog

[ROADMAP.md](ROADMAP.md) is the current list (0.0.5, Torque, builds with
no folder, Seihai). The 2026-11-05 list:

- [ ] Each folder's `Not yet` list in its `RELEASE_NOTES.md` (and the
  README's "Not yet" checklist): the per-client backlog. Examples: the
  NewWorld betas' clock and sword, 2.17.1's names, the Training view, the
  2.22 gani frame rate (the untraced movie step, #143), the 2.31 and 2.3
  water squares (#142).
- [ ] The families still open: [#100](https://github.com/squirelworks/graal-client-repro/issues/100) precursors and side builds,
  [#101](https://github.com/squirelworks/graal-client-repro/issues/101) 1998 betas to 1.1, [#105](https://github.com/squirelworks/graal-client-repro/issues/105) 2.17.1 to 2.31,
  [#106](https://github.com/squirelworks/graal-client-repro/issues/106) 3.x to 6.x; and [#108](https://github.com/squirelworks/graal-client-repro/issues/108) for 2.22.
- [ ] [#107](https://github.com/squirelworks/graal-client-repro/issues/107) the stress gate's first run on Actions.
- [ ] macOS: the framework fix in `darwin-cross.sh` (section 4), then run
  the Cocoa window on a real Mac ([#115](https://github.com/squirelworks/graal-client-repro/issues/115)).
- [ ] [#114](https://github.com/squirelworks/graal-client-repro/issues/114) a real Delphi 5 or 7 build.

## 9. Where things live

**Project files** (the shared folder of the Claude project; copied into the
tarball under `project-files/` unless noted):

- `graal-delphi/assets-0.0.4/`: the game data the 0.0.4 clients read
  (`graal-assets-0.0.4.zip`, with `README.txt` for setup, `INVENTORY.txt`,
  `FILES.txt`). Original files: never commit them, never attach them to a release.
- `graal-delphi/macos-cross/`: `setup-darwin-cross.sh` and the v0.0.4
  link failure notes.
- `graal-delphi/compare*/`, `205-vs-real/`, `222-*`, `hud-129-vs-real/`,
  `every-client-smoke/`, `notes/`: side-by-side captures and notes.
- `graal-delphi/handoff/graal-4.04r2-wip-from-3x-thread.tgz`
- `graal-delphi-gui/`, `real-a.png`, `222-serverlist.png`, `ato/`: reference shots
- `handoff/cursor/`: the Seihai server stack handoff (2026-10-31)
- Not in the tarball: old build outputs (`graal-delphi/*-win*`, `pr*-win`,
  `v0.0.*-1x-builds`, `2.22-test`, `macos-0.0.4`), the client archives
  (`*.7z`, `graal clients.zip`), `graal-decompile/` (raw decompiles,
  except the 3.x lab shots), uploads, the Mac VM. Raw decompiles never go in a repo.

**Squirrel's Windows PC**:

- `<local client folder>`: the real client installs, one folder per version (54 pairs with a rebuild)
- `<local lab folder>`: the lab (real-client runs, captures, the error-dialog watchdog)

The PC cannot build or push; code changes happen in the cloud or in Cursor.

## 10. Decisions (Squirrel's; D1 and D4 are made, the rest are open)

- **D1. Torque layer language: decided (2026-11-09), C++** under
  `common/torque/`; the v0 to v2 clients stay Object Pascal, and the late-5
  and 6.x own-engine work is a separate track. No modern Torque3D base.
  [#110](https://github.com/squirelworks/graal-client-repro/issues/110).
- **D2. 2.3**: read the unpacked exe from Drive to make the folder 2.3's
  own, or keep the stand-in. [#111](https://github.com/squirelworks/graal-client-repro/issues/111).
- **D3. d3drm.dll source** for the real Graal3D. [#112](https://github.com/squirelworks/graal-client-repro/issues/112).
- **D4. Extracted resources: decided (2026-11-05).** Squirrel set the
  assets concern aside: each exe is made as faithful as possible, with
  everything pulled out of its own real exe and wired into its
  reproduction, per client (never 2.22's set for another version). The
  extracted set goes in the folder (for example a `resources/` subfolder
  plus the `.rc`/`.res` the project links) and is compiled in. Where
  versions share identical resources, dedupe by hash but still ship them
  per folder. Clients without a real exe are made to look as authentic
  as possible from their nearest real siblings.
- **D5. Licence and code signing.** [#116](https://github.com/squirelworks/graal-client-repro/issues/116).
- **D6. 5.x/6.x Login capture** against a public server (Graal_analysis #247).

## 11. How to start in Cursor

1. Unpack the tarball. `repos/graal-delphi` and `repos/Graal_analysis` are
   full clones at `main` with every branch (open PR branches are local
   branches, listed in `BRANCHES.md`); `repos/seihai-stack/` has the Seihai
   repos; `project-files/` has the captures, test exes and reference shots.
   Set each clone's `origin` to GitHub with your own credentials before pushing.
2. Read `AGENTS.md` here and in Graal_analysis.
3. Open [ROADMAP.md](ROADMAP.md) and section 8 above. Take the next
   unchecked 0.0.5 item, one per branch and PR.
4. Before starting anything: `git fetch origin main`, check that the PRs
   you depend on are merged and that no open PR already covers the task.
