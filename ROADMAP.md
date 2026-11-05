# Roadmap

Where graal-delphi stands and what comes next, as task lists: tick an item
in the PR that does it. Per-folder detail lives in each folder's README
("Not yet") and in the issues linked here. Updated 2026-11-05.

## Levels

- **0.0.1**: first rebuild. Logs in, walks, plays as far as its README says;
  not yet compared action by action with the original.
- **0.0.1.1**: a 0.0.1 rebuilt with a fix.
- **0.0.2**: checked side by side with the original client.
- **v0.0.3**: one combined release of all 71 clients after the fidelity
  pass and the stress gate. The release number is shared; each client's
  notes say what was matched and what was not.

Where each client is today: [RELEASES.md](RELEASES.md) (from #96; latest
release per client). Today 2.05 rev 2 and 2.22 are at 0.0.2, 2.17.1 at
0.0.1.1, every other client at 0.0.1.

## v0.0.3: all clients in one release ([#99](https://github.com/squirelworks/graal-delphi/issues/99))

- [ ] #96 RELEASES.md merged
- [ ] #97 2.22 fidelity merged (remaining 2.22 items: #108)
- [ ] #98 release-all and the stress gate merged
- [ ] Real-client captures and extracted resources, all 54 real pairs
  - [x] Map rebuilt folders to installed real clients (54 pairs)
  - [x] Side-by-side runner with an error-dialog watchdog
  - [x] Resources and Delphi form layouts extracted from all 54 real exes
  - [ ] Re-shoot every pair with window size, style and control dumps
  - [ ] Bundle captures and resources per version into project files
- [ ] Fidelity pass, one PR per folder:
  - [ ] #100 precursors and side builds (5)
  - [ ] #101 gen 1, the 1998 betas to 1.1 (20)
  - [ ] #102 gen 2, 1.21 to 1.41r1 (13)
  - [ ] #103 NewMain and 2.0 to 2.05 (16)
  - [ ] #104 2.1 test builds and the NewWorld betas (5)
  - [ ] #105 2.17.1 to 2.31 (4)
  - [ ] #106 3.x to 6.x (8; look pass only)
- [ ] #107 stress gate green on Actions for all 67 Delphi clients
- [ ] Final side-by-side check on Squirrel's Windows PC
- [ ] release-all run, `v0.0.3`

During each folder's PR, also tick or remove items in that folder's
README "Not yet" list that are already done (the lists were turned into
task lists mechanically on 2026-11-05 and some are older than the code).

## After v0.0.3

- [ ] #108 2.22: the rest of the real client (launcher drop-downs and
  buttons, GS1 2.22 additions, NPC props past 40, editors, chat bubbles)
- [ ] #109 3.x and later: the Torque-faithful rebuild, stages 0 to 10
  (on hold; needs Graal_analysis #242 and the decision in #110)
- [ ] #111 2.3 from a real 2.3 exe (on hold)
- [ ] #112 Graal3D side by side (on hold: d3drm.dll)
- [ ] #113 4.04r2 side by side (on hold: the real client crashes)
- [ ] #114 a real Delphi 5 or 7 build
- [ ] #115 a macOS window
- [ ] #116 licence and code signing (Squirrel decides)
- [ ] Phase 4 for every build: headless mode, fuzzed receive path, leak
  checks, and a place in the Seihai 1000-player stress runs. The 2.0 to
  2.05 folders and 2.22 have a "Stress runs (phase 4)" section; 2.17.1
  carries 2.05's; the rest pass `scripts/stress.sh` (#98) only
- [ ] Phase 5 kept current: every merged fix gets a release-notes line
  and goes out with the next combined release
