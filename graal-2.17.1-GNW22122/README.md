# Graal 2.17.1 (`GNW22122`)

The 2.1.7.1 client, rebuilt. Original: `Graal_2171.exe`, 2,180,096 bytes,
a Delphi build of the same family as 2.05 (same network classes, same
cipher LCG).

This build starts from a copy of the [2.05 rev 2 rebuild](../graal-2.05r2-GNW03081/)
and changes what 2.17.1 is known to do differently. Anything not listed
under "Differences from 2.05" behaves as the 2.05 rebuild does until a
difference is found.

## Sources

Written from the notes in
[graal_analysis](https://github.com/squirelworks/graal_analysis), not from
decompiled code:

| Area | Notes |
|---|---|
| 2.05 against 2.17 | `protocol/client-versions.md` |
| Login, tamper check | `protocol/lab-checks-2026-10-24.md`, `version-profiles/tampercheck-values.tsv` |
| Server ids handled | `version-profiles/plo-handled-ids-by-build.tsv`, `protocol/packet-layouts.md` (ids above 48) |
| Prop streams | `version-profiles/plo-playerprops-layouts.tsv`, `plo-otherplprops-layouts.tsv` |
| Props the client sends | Seihai lab trace of the real 2.17.1 (`difftest-217-2026-10-30`) |

## Differences from 2.05 (done)

- Token `GNW22122`. Login stays type 0 with the gen-3 cipher and zlib
  frames, as in 2.05.
- After `PLI_LANGUAGE`, `PLI_TAMPERCHECK` (39) goes out once with the 10
  bytes the real 2.17.1 sends (test).
- Prop 10 is the GANI name (a string), not the bow. Other players' poses
  come from it and run with time.
- The sprite prop carries the direction only; the pose goes out as GANI.
  Props go out in the real client's order: GANI, X, Y, SPRITE. At session
  start PLANGUAGE (52) follows 2.05's set.
- The own prop stream takes ids up to 74 and stops at 50, 51 and 53.
- `PLAYERWARP2` (49) moves the player; the gmap itself is not drawn yet.
- Ids 68, 69 and 169 to 185 are accepted and ignored for now.
- A GUI program, like the original: with no arguments it opens the shared
  start screen (`common/GStartScreen.pas`). `src/StartScreen217.pas` plugs
  in 2.17's list step: one plain zlib frame holding id 0 `newmain` and id 1
  with the account and password, sent when the list page opens and on
  Refresh. The listserver comes from `arrays2.dat` in the program's folder
  (line 0 host, line 1 port), as 2.17 reads it; `listserver.txt` wins over
  it; with neither, 127.0.0.1:14921. Training starts at
  `offlinetutorial_b-2.graal` when it lies next to the program, else at the
  built-in `start.nw`. The built-in original assets fill in for anything
  not on disk (tests).
- Loopback: two 2.17.1 clients log into seihai-gserver, see each other and
  walk through a link (`scripts/loopback.sh`, run in CI).

## Not yet

- Which ids other players' prop stream stops at was not isolated in the
  notes; it takes the same range as the own stream here [inf].
- Gmaps, the ids 169 to 185 (ghost mode, server maps, serverwarp, RPG
  window, status list, process list, screenshots, level heights), large
  file downloads.
- The `arrays2.sig` check of `arrays2.dat`.
- The arrival point on `offlinetutorial_b-2.graal` (30, 30 is a guess).
- Chat-line emoticons and the rest of what 2.17.1 added over 2.05.
- The link test point was measured on 2.05, not on 2.17.1.
- Everything listed under "Not yet" for 2.05.

## Build and run

As for 2.05: `scripts/build.sh graal-2.17.1-GNW22122`, `scripts/test.sh`,
then `Graal217` with no arguments for the start screen, or with the same
flags as `Graal205`. A 2.2.2-era install
(with `levels/ganis`) works as `--data`.
