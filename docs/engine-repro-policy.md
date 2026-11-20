# Engine repro policy (3.x–6.x)

Owner decision for classic 3.x through 6.x client folders: each folder
keeps **two** reproduction tracks, and only the track that currently works
end-to-end is the release / no-argument default. This page is the policy;
runtime defaults flip in separate, validated PRs — not in a docs-only
change.

Out of scope here: Graal3D 2000/2001 folders, 39ster, Java / Zelda Online /
Game Boy, and Worlds 7.x. Those lines follow their own READMEs.

## The two tracks

| Track | What it is |
|---|---|
| **Delphi / Pascal stand-in** | The Object Pascal client that already builds and plays as far as that folder's README says (start screen, list or Login path, level, walk, chat, stress flags). |
| **Faithful engine wiring** | The attempt to run that build the way the original did: Torque for early 3.x, Delphi launcher plus shared engine library for mid-4.x / early 5.x, Quattro program for late 5.x and 6.x. Shared engine code lives under `common/` (Torque, GS2 / engine library, Quattro). |

Both tracks stay in the tree for every in-scope folder. The engine track may
be partial (boot host, `--engine` flag, scaffold, sibling binary). Partial
is fine; deleting either track is not.

## Default vs relic

- **Default** = whatever the folder releases and what a no-argument start
  uses today, provided that path works end-to-end for that folder's stated
  play loop.
- **Relic / fallback** = the other track, kept on purpose after the
  faithful engine has become the default. Label it clearly in the folder
  README. Never delete it. Operators and tests may still force the relic
  (for example a dedicated flag or env) when the engine binary is missing
  or a headless / CLI path still needs Pascal.
- Until the faithful engine is validated end-to-end for that folder,
  **Pascal remains the default**. The engine track is "still being wired",
  not a relic yet. Docs may describe the intended switch; they must not
  pretend the switch already happened.

Docs-first rule: README and policy updates that name default / relic do
**not** by themselves change binaries, scripts, or no-argument behaviour.
Flipping a default is a separate change, only after E2E validation against
loopback servers you start yourself.

## Per-folder README lines

Every in-scope folder README carries a short **Repro tracks** block that
names:

1. which track is **default** right now, and
2. which track is **relic** (or that there is no relic yet because the
   engine track is still being wired).

Update those two labels in the same PR that flips the runtime default.

## Relationship to live engine work

This policy does not replace the live engine epics or open wiring PRs
(Torque entry work, engine-library sessions, Quattro play). Those stay the
implementation path. The tracking issue for "faithful engine switched to
default vs still being wired" is the checklist; tick a folder only when
its release default actually moved and the Pascal track is labeled relic.

## Placeholders

Public notes use placeholders only for accounts, hosts, ports, install
roots, and lab machine names. No third-party private dumps, no raw
decompile material, and no secrets in this doc or in folder README lines.

The step-by-step guide (e2e lab, order of work, how to switch a folder) is
[ENGINE-HANDOFF.md](ENGINE-HANDOFF.md).
