# Roadmap

Where graal-delphi stands and what comes next, as task lists: tick an item
in the PR that does it. Per-folder detail lives in each folder's README
("Not yet") and in the issues linked here. Updated 2026-11-05 (evening).

## Levels

- **0.0.1**: first rebuild. Logs in, walks, plays as far as its README says;
  not yet compared action by action with the original.
- **0.0.1.1**: a 0.0.1 rebuilt with a fix.
- **0.0.2**: checked side by side with the original client.
- **v0.0.3, v0.0.4**: combined releases of all 71 clients; each client's
  notes say what was matched and what was not.

Every client is at **v0.0.4** ([RELEASES.md](RELEASES.md)). 0.0.5 is
Cursor's, from 2026-11-07.

## Done

- [x] Every client in a folder of its own (#56 to #90)
- [x] RELEASES.md, latest release per client (#96)
- [x] One-click release-all (#98) and the combined releases v0.0.3 and v0.0.4
- [x] Faithfulness pass from each real exe: #102 (1.21 to 1.41r1), #103
  (NewMain and 2.0 to 2.05), #104 (2.1 tests and NewWorld betas) closed;
  launcher, icon, game window and HUD work for every family (#118 to #141)
- [x] Torque stage 1 script VM parked on main, compiling (#145)

## 0.0.5 (Cursor)

- [ ] The `Not yet` list in each folder's `RELEASE_NOTES.md` and README:
  the per-client backlog (for example the NewWorld clock and sword,
  2.17.1's names, the Training view, the 2.22 gani frame rate)
- [ ] #100 precursors and side builds: remaining folders
- [ ] #101 1998 betas to 1.1: remaining folders
- [ ] #105 2.17.1 to 2.31: remaining folders
- [ ] #106 3.x to 6.x: look pass for the remaining folders
- [ ] #108 2.22: the rest of the real client
- [ ] #107 stress gate: first run on Actions
- [ ] macOS: framework path in `scripts/release/darwin-cross.sh` so the
  Cocoa window links (notes in project files, `graal-delphi/macos-cross/`),
  then run it on a real Mac (#115)
- [ ] #114 a real Delphi 5 or 7 build

During each folder's PR, also tick or remove items in that folder's
README "Not yet" list that are already done (the lists were turned into
task lists mechanically on 2026-11-05 and some are older than the code).

## On hold

- [ ] #109 3.x and later: the Torque-faithful rebuild. **On hold, no
  target release** (Squirrel, 2026-11-05). The stage 1 VM is in
  `common/torque/` (README lists the next steps); decision #110 is moot
  until it resumes
- [ ] #111 2.3 from a real 2.3 exe
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
