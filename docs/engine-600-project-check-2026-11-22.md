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

## Remaining acceptance

- [x] Direct Linux-built project profiles: login, authored board, real-key walk,
  level-link transition and bounded clean exit, for both labels.
- [ ] Windows Pascal `--engine` launcher and start-screen handoff.
- [ ] Server-list/login-to-game warp chain, second-player visibility, chat,
  weapons/actions and the full soak checklist in [ENGINE-HANDOFF](ENGINE-HANDOFF.md).
- [ ] Original-client/native behavior, inherited send/property contracts and
  macOS execution validation.
- [ ] Default-switch gate. The no-argument route remains Pascal.
