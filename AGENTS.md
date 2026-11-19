# Agent rules for graal-delphi

Owner: Squirrel (GitHub `squirelworks`). Agents (Claude, Cursor) open PRs;
they never merge their own PR, never push to `main`, and never create a tag
or release by hand. Start with [HANDOFF-CURSOR.md](HANDOFF-CURSOR.md) and
[ROADMAP.md](ROADMAP.md).

## What may go in the repo

- No original Graal code. Game data (tiles, ganis, heads, bodies, levels)
  is loaded from the player's own install at run time (`graal-assets/`,
  `docs/assets.md`). Each folder carries its real exe's resources in
  their original shape (names, sizes, formats, form layouts, string
  tables), but every picture and level in them is graal-delphi's own art
  from `scripts/art/make_art.py` (docs/art.md, decision 2026-11-19); CI
  fails otherwise (`make_art.py --check`). The original files go in the
  player's `assets/` folder, never in the repo. Never another version's set.
- No raw decompile material anywhere (source, comments, commits, PR text):
  no code or data addresses, RVAs or file offsets, no `FUN_` / `DAT_` /
  `LAB_` names, no decompiled C. Write behaviour from the Graal_analysis
  notes, which tag their evidence.
- No real server hosts, IPs or public ports in tests or docs beyond what
  the README already names; tests use loopback servers you start.

## How a change goes in

- Verify merge state first: `git fetch origin main`, check that PRs you
  depend on are merged and that no open PR covers the task. Do not stack
  on an unmerged PR.
- One change per branch and PR. A folder PR touches its own folder only
  (and `common/` when a shared unit truly changes for every build that
  uses it). **Folder PRs never touch the root `README.md`**; root docs get
  their own PR.
- Every PR body starts with the attribution block:

  ```
  <!-- claude-projects-attribution: {"github_login":"squirelworks"} -->
  _Requested by **Squirrel** · [project thread](<link>)_
  ```

- `scripts/build.sh` and `scripts/test.sh` pass locally (no unfreed
  memory); a new folder runs `python3 scripts/win/make_winres.py`.
- Each fix for the next combined release is a bullet under
  `## What's new in v0.0.3` (or the current version) in the folder's
  `RELEASE_NOTES.md`; anything not fixed goes under `Not yet` as a known
  limitation.
- Tick the matching `- [ ]` item (folder README "Not yet", ROADMAP.md, the
  issue) in the same PR. Every incremental fix list is a GitHub task list.

## Releases

- All clients release together at one version from
  `.github/workflows/release-all.yml` (Squirrel runs it). No per-folder
  tags or releases in between.
- `RELEASES.md` lists only the latest release of each client.
- Versions have three parts (VERSIONING.md): a respin of the combined release
  with fixes is the next patch (v0.0.5, v0.0.6, ...), never a fourth digit.
  0.1.0 is the focus-versions milestone (#410); the 1.0.0 bar is #411.

## Fidelity work

- The goal is behaviour, not looks (`docs/functional-parity.md`, owner
  decision 2026-11-19). Match each folder against **its own** real
  client's behaviour: wire, session flow, play, scripts, file requests,
  and the controls it offers. Window sizes, fonts, artwork and pixel
  matches no longer gate a release; look work already merged stays.
  Never reuse another version's behaviour profile.
- A folder with no real exe is modelled on the nearest real sibling on
  each side plus the Graal_analysis version profiles; its notes say which.
- Squirrel's Windows PC is used only to run the real clients for captures
  and the final check. Build, test, stress and diff in CI or the cloud.

## macOS builds

macOS is built and tested by `.github/workflows/macos.yml` on GitHub's hosted macOS 15 runners, with the same build and test commands the Linux jobs run. It runs on demand (`workflow_dispatch`), weekly, and on a PR that changes it; the per-PR workflows cover Linux and Windows. The lab's Sequoia VM is for reproducing a macOS failure by hand.
