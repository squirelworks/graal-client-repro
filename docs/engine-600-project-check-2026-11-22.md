# 6.00r4 and 6.00b2: bounded direct Quattro project check

2026-11-22. This checks the reconstructed project's two profiles against an
own loopback Rust project server in a Linux guest. It is not an original-client
comparison, a Windows Pascal launcher check, or the full default-switch gate.

## Builds and fixture

The controller recorded the client source as the accepted [beta2 implementation commit](https://github.com/squirelworks/graal-client-repro/commit/2768746a5471c4d36693a08e1409473de021c157),
which includes the r4 implementation. The guest built `quattro-play` with X11;
the selected labels were `6.00r4` and `6.00b2`. Both still inherit the behavior
limits documented by their implementation PRs, [#439](https://github.com/squirelworks/graal-client-repro/pull/439)
and [#440](https://github.com/squirelworks/graal-client-repro/pull/440).
A separate source-content check found all 137 regular files in the selected
client source archive match that commit after CRLF-to-LF normalization only.
They are not byte-identical archive files or the full repository, and this
comparison does not attest the running client binary.

The Rust project server was a retained binary, not a fresh server build. Its
source commit could not be established: an adjacent checkout is not a
binary/source binding. The server therefore remains an unknown-source retained
build for this receipt. Login tokens shared with other versions do not
authenticate the selected build; the selected client label and recorded source
are separate from the server token label.

Each run used a disposable project-world copy and the existing loopback script's
test-account contract. Two authored NW levels were joined by the script's
right-edge link. The only tile art was authored test data; collision data marked
tile zero passable and supplied an empty liquid set. No original client, art or
archive was used. The server and client stayed inside the guest on loopback.

## Results

For each profile, the server accepted login and the client displayed the authored
board. A real Right-key hold of 0.6 seconds moved the player through the link.
The server account receipt changed from the start level at `(30, 30.5)` to the
linked level at `(4, 30.5)`; the client summary named the linked level with lobby
mode off. Both bounded client runs exited with status zero. The controller reported
cleanup of the owned processes, but no standalone post-run process inventory
was retained; the normal exits and cleanup trap are not independent cleanup
verification. Retained build, before/after and screen receipts are private; no
captures or artwork are published here.

Two earlier setup failures were retained. The default `--server-name Login`
selects lobby behavior even when connecting directly to a game port; that run
logged in and loaded a level but did not walk. The corrected invocation supplied
an explicit non-Login game name. A zero-filled collision fixture then parsed as
an empty passability set and blocked movement; correcting the authored fixture
to include tile zero enabled the measured walk. Neither result established an
engine code defect, and no production code was changed for this check.

## Follow-up: two-player visibility and position updates

A separate 35-second pair for each label reused the controller-recorded client
build, authored assets and retained unknown-source server above; no rebuild was
performed. The two accounts started on the same level at x=18 and x=25, both
at y=30.5. Each client's initial frame visibly contained its own red placeholder
and the other player's blue placeholder, with both distinct names.

Only A received a real 0.2-second Right-key hold. In these runs its persisted
x changed from 18 to 20.5, while B stayed at 25; level and y were unchanged.
The stationary B view showed the peer move right while its own placeholder
stayed fixed, for both profiles. This checks rendered peer-position updates,
not exact input timing, movement rate or packet equivalence.

Both servers logged two accepted players and normal client closes. All four
clients exited with status zero. Unlike the earlier smoke runs, each peer pair
has a saved timestamped post-run process inventory: none of its recorded client,
server or display-server PIDs remained after the cleanup trap waited for them.
This cleanup evidence applies only to these peer runs. It does not upgrade the
earlier controller-reported cleanup observation.

Actual logs, seed/final account snapshots and before/after views were read in
review; no captures or account files are published. Only the direct project
"see each other" item is completed here. Those peer-only runs did not include the long soak, and no chat, weapon,
native-client or Windows launcher acceptance follows from them.

## Separate five-minute no-input connection soak

A later pair for each label reused the same recorded client build, authored
fixture and retained unknown-source server. Neither client received gameplay
input. Timing began only after both server logins were recorded, with the same
client PIDs checked at 60, 120, 180, 240 and 300 seconds.

The r4 end captures followed 301.3 seconds after that anchor; beta2 followed
300.8 seconds. Both end views still contained both players. Server logs record
only the expected normal client closes at about 310 seconds per connection;
no unexpected disconnect was recorded during the measured intervals. All four
client exits and both bounded runner exits were zero. Each soak pair has its
own saved post-cleanup inventory, with none of its recorded owned PIDs present.
This does not change the earlier smoke run's cleanup evidence.

The controller recorded unchanged server policy: `heartbeat = 5`, `ping = 0`,
and `idle_timeout = 0`. Post-run configuration snapshots agree with those
values, but are not contemporaneous captures or independent proof of policy
immutability during the run. This supports bounded idle connection stability
under that recorded configuration, not enforced keepalive, ping-timeout or
idle-eviction behavior.
It does not establish active-gameplay/churn stress, memory-leak freedom, chat,
weapons, native fidelity, launcher handoff or the complete end-to-end gate.
The source/binary provenance limits above still apply.

## Remaining acceptance

- [x] Direct Linux-built project profiles: login, authored board, real-key walk,
  level-link transition and bounded clean exit, for both labels.
- [ ] Windows Pascal `--engine` launcher and start-screen handoff.
- [x] Direct project two-player visibility and rendered peer-position updates
  for both labels, in separate bounded pairs.
- [x] Separate direct-project no-input pairs remained connected for at least
  five minutes after both logins, under the recorded server policy.
- [ ] Server-list/login-to-game warp chain, chat, weapons/actions and the
  combined full checklist in [ENGINE-HANDOFF](ENGINE-HANDOFF.md).
- [ ] Original-client/native behavior, inherited send/property contracts and
  macOS execution validation.
- [ ] Default-switch gate. The no-argument route remains Pascal.
