# Handoff to Cursor (from 2026-11-07)

Read this first. It says what graal-delphi is, how the work here is run, what
changed in the last days, what is on hold and why, where everything lives,
and which decisions are still open. The rules are short and binding; they
are also in [AGENTS.md](AGENTS.md) and `.cursor/rules/graal-delphi.mdc`, so
Cursor applies them on every request.

State as of 2026-11-05. It is refreshed on Friday 2026-11-06 with whatever
lands by then; the "What changed" and "Open PRs" sections say what moved.

Owner: Squirrel (GitHub `squirelworks`).

## 1. What the project is

Two public repos, worked on together:

| Repo | What it is |
|---|---|
| [graal-delphi](https://github.com/squirelworks/graal-delphi) (this repo) | Faithful rebuilds of every classic Graal Online client, one folder per build, in Delphi (Object Pascal), built with Free Pascal 3.2 in Delphi mode. 71 client folders: 67 Delphi clients from the 1998 betas to 6.03r7, plus Java (Zelda Online 1 and 2, Java Graal) and the Game Boy Color demo. |
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
- **Releases.** No tags or releases by hand. v0.0.3 is **one combined
  version for all 71 clients**, released in one action (see section 4).
  No per-folder releases or tags until then.
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
scripts/           build.sh, test.sh, loopback.sh, relay98.py, stress.sh (#98), release/ (#98), win/, assets/, builtin/
docs/assets.md     the graal-assets/ folder, search order per build
.github/workflows/ ci.yml (Linux, Windows, loopback), release.yml (one folder),
                   release-all.yml (#98, all clients), per-client workflows for Java/GB/3D
RELEASES.md        (#96) one row per client: its latest release
ROADMAP.md         project-level checklist and where each client stands
```

Folder naming: `graal-<version>-<token>`, the token exactly as the build
sends it on the wire (README, "Folder naming rule").

Build and test (Linux): `sudo apt-get install fp-compiler fp-units-base fp-units-fcl libx11-dev`,
then `scripts/build.sh` and `scripts/test.sh`. Tests run with range and
overflow checks and the heap tracer and must end with no unfreed memory.
A new folder needs `python3 scripts/win/make_winres.py` or CI fails.

## 4. Release flow

- **Before #98:** `.github/workflows/release.yml`, run per folder (Actions
  tab, folder name and version, or by pushing the tag `<folder>-v<version>`),
  builds that folder and makes a draft release whose text is the folder's
  `RELEASE_NOTES.md`; Squirrel presses Publish.
- **After #98 (the one-click release):** Actions → **release-all** → Run
  workflow, version `v0.0.3`. It (1) checks every `RELEASE_NOTES.md`
  mentions the version, (2) builds and tests every client on Linux and
  Windows and stamps the version into each exe, (3) runs the **stress
  gate**, `scripts/stress.sh` per Delphi client against a local
  seihai-gserver (soak with walkers crossing a level link, connect and
  disconnect churn with killed sessions, 80 scripted NPCs, memory growth
  check; relay builds against `relay98.py`; Graal3D offline), (4) publishes
  one release per folder, tag `<folder>-v0.0.3`, and (5) updates
  `RELEASES.md`. `stress_gate = report` releases even if a client fails;
  `publish = no` makes drafts. Java and Game Boy release through their own
  workflows, called from release-all.
- **RELEASES.md** lists only the **latest** release per client, one row
  each, with a link to the releases page for history (Squirrel's rule).
- Each folder's v0.0.3 changes go as bullets under
  `## What's new in v0.0.3` in its `RELEASE_NOTES.md`. Anything that can't
  be fixed goes under `Not yet` as a known limitation; it does not block
  the release.

Tracking: [#99](https://github.com/squirelworks/graal-delphi/issues/99).

## 5. What changed recently (2026-11-04 to 11-05)

- **Every client has a folder of its own** (#56 to #90): the 1998 betas,
  1.1.9 and 1.1, 1.21 to 1.41r1, NewMain 24 and 26, every 2.0x revision,
  the 2.1 tests, the NewWorld betas, Graal3D, the Game Boy demo, and the
  3.x to 6.x builds. All released at **v0.0.1**.
- **0.0.2** (checked side by side with the real client): 2.05 rev 2
  (Training under Wine: chat, chests, throwing, bombs, baddy) and 2.22
  (new-world ground by height, 2.22 baddies, listserver failure reasons,
  #91, #93). 2.17.1 is at **0.0.1.1** (the listserver hostname fix, #77).
- **2.22 fidelity, #97** (open, merging): no default helmet, key-colour
  body recolouring, no WANTFILE for `#` images, nicknames under NPCs,
  neighbour gmap cells' NPCs, sword and glove HUD icons, white chat bar,
  Training from the real tutorial map in `Graal_222.exe`, Graal head icon,
  the real 577x416 launcher and server-list windows built from the exe's
  own art and layout, nickname and account from the registry, NPC names in
  `TEMPSITC.TTF`. Remaining items: #108.
- **RELEASES.md, #96** (open): one table, latest release per client.
- **One-click release, #98** (open): `release-all.yml`, the stress gate,
  and a v0.0.3 section in every `RELEASE_NOTES.md`. All 67 Delphi clients
  passed `scripts/stress.sh` in a cloud run; it has not run on Actions yet (#107).
- **v0.0.3 fidelity pass under way** (#100 to #106): every real client on
  the PC (54 pairs) is shot side by side with its rebuild, and every
  resource embedded in each real exe (icons, bitmaps, version info, string
  tables, each Delphi form's exact layout) is extracted. 51 of 54 start
  screens were captured; 9th alpha and the 2.1 tests need a re-shoot now
  that missing files are in place. A second pass records each window's
  size, border and title-bar buttons. Fixes then go to cloud sessions per
  family as one PR per folder.
- **Window flow rule** (Squirrel): the real launcher *is* the start
  screen, its own small form sized to the art, with only the buttons the
  real one has (2.22: close button only, no resize); then the server list
  window; only then the game window at its real size.
- **Real-client launch fixes on the PC**: `zlib.dll` copied into the 2.02
  installs, `commands.rtf` into 9th alpha and the 2.1 tests,
  `headsconfig.txt` into nm24. A watchdog closes any error dialog.
- **Graal_analysis**: TRM 0.0.3 and 0.0.4 published (377 pages); the
  1.0.0 roadmap is a checklist in Graal_analysis #191 (0.0.5 next). The
  Torque study (#242, open) explains why 3.x+ folders stay at 0.0.1.

## 6. On hold, and why

| Item | Why | Issue |
|---|---|---|
| 3.04 and later past 0.0.1 | The real 3.x+ clients are Torque applications (scripts, GUI, fonts, `GuiGraalCtrl`); the folders reproduce only the wire. Squirrel put Torque on hold (2026-11-05: full speed on the clients before 3.x), targeted at **v0.0.4**. An unfinished stage 1 script VM (about 3,800 lines of Pascal, never compiled) is parked on branch `claude/project-thread-b0180m` in `common/torque/`, whose README lists the three next steps. #95 (2.22 play layer on the 3.04 wire) closed, on hold. | [#109](https://github.com/squirelworks/graal-delphi/issues/109), [#110](https://github.com/squirelworks/graal-delphi/issues/110), Graal_analysis #242, #243 |
| 2.3 as its own client | No real 2.3 exe has been read; the folder is the 2.31 rebuild with 2.3's token. #94 (remove it) closed, so it stays. An unpacked 2.3 is on Squirrel's Drive. | [#111](https://github.com/squirelworks/graal-delphi/issues/111) |
| Graal3D side by side | The real client needs `d3drm.dll`, which modern Windows lacks; none on the PC, not downloaded from unknown sites. | [#112](https://github.com/squirelworks/graal-delphi/issues/112) |
| 4.04r2 side by side | The real client crashes on start (access violation; its folder holds only the exe). | [#113](https://github.com/squirelworks/graal-delphi/issues/113) |
| Code signing, licence | Owner decisions. | [#116](https://github.com/squirelworks/graal-delphi/issues/116) |
| Graal_analysis items | pyReborn files (#244), 2.1 to 2.16 builds (#245), 1.32 export (#246), 5.x/6.x Login capture (#247). | Graal_analysis |

## 7. Open PRs (2026-11-05)

| PR | What | State |
|---|---|---|
| graal-delphi #96 | RELEASES.md, latest per client | CI, then merge |
| graal-delphi #97 | 2.22 heads, NPCs, Training, real start window | lab re-run of test2, CI, then merge |
| graal-delphi #98 | release-all v0.0.3 and the stress gate | merge after the fixes; then the dry run (#107) |
| Graal_analysis #242 | Torque study and the 3.04 plan | review by the maintainer |

In the tarball each open PR's branch is a local branch of the clone (`git branch` lists them; `BRANCHES.md` maps PR to branch).

## 8. Where things live

**Project files** (the shared folder of the Claude project; copied into the
tarball under `project-files/` where listed):

- `graal-delphi/2.22-test/`: 2.22 test exes (`Graal222-0.0.3-test1.exe`, `-test2.exe`)
- `graal-delphi/handoff/graal-4.04r2-wip-from-3x-thread.tgz`
- `graal-delphi-assets/graal-assets.zip`: the assets folder the clients read (originals; never commit)
- `graal-delphi-gui/`, `real-a.png`, `222-serverlist.png`, `ato/`: reference shots
- `handoff/cursor/`: the Seihai server stack handoff (2026-10-31)
- the client archives (`*.7z`, `graal clients.zip`) and `graal-decompile/`
  (raw decompiles): **not** in the tarball, and never in a repo
- per-version captures and extracted resources from the side-by-side run:
  copied in when they land (Friday refresh)

**Squirrel's Windows PC**:

- `<local client folder>`: the real client installs, one folder per version (54 pairs with a rebuild)
- `<local lab folder>`: the lab (real-client runs, captures, the error-dialog watchdog)

The PC cannot build or push; code changes happen in the cloud or in Cursor.

## 9. Decisions (Squirrel's; D4 is made, the rest are open)

- **D1. Torque layer language**: Object Pascal in graal-delphi
  (recommended) or C++ in its own tree. [#110](https://github.com/squirelworks/graal-delphi/issues/110).
- **D2. 2.3**: read the unpacked exe from Drive to make the folder 2.3's
  own, or keep the stand-in. [#111](https://github.com/squirelworks/graal-delphi/issues/111).
- **D3. d3drm.dll source** for the real Graal3D. [#112](https://github.com/squirelworks/graal-delphi/issues/112).
- **D4. Extracted resources: decided (2026-11-05).** Squirrel set the
  assets concern aside: each exe is made as faithful as possible, with
  everything pulled out of its own real exe and wired into its
  reproduction, per client (never 2.22's set for another version). The
  extracted set goes in the folder (for example a `resources/` subfolder
  plus the `.rc`/`.res` the project links) and is compiled in. Where
  versions share identical resources, dedupe by hash but still ship them
  per folder. Clients without a real exe are made to look as authentic
  as possible from their nearest real siblings.
- **D5. Licence and code signing.** [#116](https://github.com/squirelworks/graal-delphi/issues/116).
- **D6. 5.x/6.x Login capture** against a public server (Graal_analysis #247).

## 10. How to start in Cursor

1. Unpack the tarball. `repos/graal-delphi` and `repos/Graal_analysis` are
   full clones at `main` with every branch (open PR branches are local
   branches, listed in `BRANCHES.md`); `repos/seihai-stack/` has the Seihai
   repos; `project-files/` has the captures, test exes and reference shots.
   Set each clone's `origin` to GitHub with your own credentials before pushing.
2. Read `AGENTS.md` here and in Graal_analysis.
3. Open [ROADMAP.md](ROADMAP.md) and issue #99. Take the next unchecked
   item, one per branch and PR.
4. Before starting anything: `git fetch origin main`, check that the PRs
   you depend on are merged and that no open PR already covers the task.
