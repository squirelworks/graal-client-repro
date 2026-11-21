# Engine handoff: end-to-end tests, finishing the engines, switching defaults

For whoever picks up the engine work (Codex, Cursor, people). This page is
the order of work, not the facts behind it: the facts are in
[v3-v6-plan.md](v3-v6-plan.md), the engine READMEs and Graal_analysis.
The policy is [engine-repro-policy.md](engine-repro-policy.md). Status is
tracked in [#403](https://github.com/squirelworks/graal-client-repro/issues/403).

Rules that do not bend: no original Graal code or files in the repo, no
raw decompile material, no real server hosts (127.0.0.1 only), no lab
captures in PRs (derived tables only), one properly sized PR per step,
never merge your own PR or tag.

## Where it stands (2026-11-20)

Ten of the 36 3.x to 6.x folders start their faithful engine with no
arguments:

| Generation | Engine | Default today | Next |
|---|---|---|---|
| 3.0beta, 3.01, 3.04, 3.151, 3.153 | Torque rebuild `graal304-torque` (`common/torque`) | engine | Debian lab check (#303); 3.153 boot profile; 3D |
| 4.02.11 to 4.20r8 (12 folders) | engine library `common/cpp/graalengine` behind `--engine` | Pascal | finish the library (below), then e2e and switch |
| 5.00r7, 5.12, 5.12mac | same library (5.0 profile) | Pascal | as 4.x |
| 5.24r4, 5.31r4 | Quattro `quattro-play` (`common/cpp/quattro`) | engine | e2e lab like 6.03r7 |
| 6.01r1, 6.03r7 Linux, 6.03r7 Windows | Quattro | engine | gaps in #430 |
| 6.00r4 | Quattro `quattro-play`, explicit `--engine` | Pascal | validate inherited behavior and e2e before default switch |
| 6.00b1, 6.00b2, 6.00beta, 6.004mac, 6.0.1.5, 6.015mac, 6.0.3.4 | Quattro (no profile row yet) | Pascal | add a profile row, hand off, e2e, switch |
| 6.1.1.3, 6.11r1 Mac | connector clients | Pascal | connector cipher end to end (#429), then Quattro |

## 1. Run the end-to-end tests

### 1a. In CI and on any Linux box (every PR)

```
scripts/build.sh graal-6.03r7-G3D0511C          # also builds quattro-play
make -C common/cpp/quattro test                  # Quattro unit and program tests
make -C common/cpp/graalengine test              # engine library tests
scripts/loopback.sh /path/to/seihai-gserver graal-6.03r7-G3D0511C
scripts/stress.sh  /path/to/seihai-gserver graal-6.03r7-G3D0511C 120
```

`seihai-gserver` is the Rust server (`squirelworks/seihai-gserver`,
`cargo build --release`). `loopback.sh` logs two copies of the client in,
checks both load the board, that the second sees the first, and walks one
through a level link. `stress.sh` soaks three clients. Both use
127.0.0.1 only. The Pascal 6.1.1.3 / 6.11r1 suites:
`fpc -Mdelphi -Fu../../common -Fu../src tests/Test6113.dpr`, run from the
repo root.

### 1b. The full lab chain (before switching a default)

This is what `graal-6.03r7-G3D0511C/docs/e2e-lab-2026-11-20.md` ran.
Use a headless lab VM (never bare metal), Xvfb for the windowed client.

1. **Servers**, all on 127.0.0.1 in the VM:
   - `seihai-listserver` (registers the servers, serves the list).
   - A Login server: the GServer-v2 fork (`seihai-gserver-v2`, gs2emu)
     with `serverside = true`. Its start level holds an NPC that does
     `serverwarp` to the game server, so the client receives S>C 178.
   - Game server pass 1: the same fork, two levels joined by a
     right-edge link, plus Bomb, Bow and a GS2 weapon that sets
     `player.chat`.
   - Game server pass 2: the Rust `seihai-gserver`, its world made with
     `seihai-gserver import-v2` from the same folder. Check that the
     build's token is allowed (`allowedversions.txt`).
   - Optional: a decoding proxy in front of each server that logs both
     directions and can inject a packet (for 108 and other probes).
2. **Clients:**
   - A: the folder's start screen on Xvfb: nick, account, server list,
     Connect. It must hand the game to its engine.
   - B: the engine directly, e.g.
     `quattro-play --build 6.03r7 --connect 127.0.0.1:<login port>`.
3. **Checklist** (each is pass or fail, both clients, both passes):
   server list; login, 178 warp, game level; straight to the game server;
   walk (position diffs each tick); see each other (S>C 8); chat both ways
   and drawn; GS2 weapon (33, 197, 158, 140); bomb and bow on the wire and
   drawn; a level link followed by the client; 46 on every entry (6.x);
   108 answered with 162; a soak of at least 5 minutes with no disconnect.
4. **Write up** a derived table as `<folder>/docs/e2e-lab-<date>.md`
   (no pcaps, logs, screenshots or hosts), link it from the folder README,
   and file client gaps as issues.

## 2. Finish the engines (order of work)

1. **Quattro, 6.x first (#305, #373, #430).** Cheapest wins.
   - Fix the #430 gaps on 6.03r7 (keep-alive 24 once evidenced, bomb and
     arrow art, chat font).
   - Add a `BuildProfile` row in `common/cpp/quattro/net/profile.cpp` for
     each 6.00x / 6.0.x / Mac build from Graal_analysis
     `protocol/v6x-clients.md` (token, login line, PLO/PLI id sets, ping,
     own-prop rules). Add a program test per row like
     `test_program_603_*`.
   - Hand the folder's start screen to `quattro-play` with
     `common/GQuattroPlay.pas`, as `graal-6.03r7-G3D0511C/src/Graal603.dpr`
     does, and add the folder to the Quattro list in `scripts/build.sh`.
   - Remaining long-tail GS2 builtins (`serverwarp`, ...), plan item D2+.
2. **Connector clients (#429).** The project script that sends the
   `0xfd`/`0xfc` key frame, the socket loop calling `Cipher6113`, the
   server side in seihai-gserver-v2, then the Mac and Worlds scaffolds.
   Then put 6.1.1.3 / 6.11r1 on Quattro.
3. **The 4.x / 5.0 engine library (#304), the biggest piece.**
   `common/cpp/graalengine`: the launcher (`common/GEngineHost.pas`)
   loads it with `--engine`. Menus, login, level, walk and chat work on
   4.04r2. Still open (its README's checklist): the map and weapon/item
   menus, saving options, the canvas cursor and hint, double-click events,
   flash panels and external windows; `TShowImg` and the 2D game behind
   the playfield (plan B5); `GRPKG001` packages and `GR-V1.05` layers
   (B6b); 3D for `"3 "` servers (C4). Bring 4.11 Mac to 4.04r2's depth.
   Work 4.04r2 first, then each folder's wire row (4.02.11, 4.03r1,
   4.03r3, 4.11, 4.20r6, 4.20r8, 5.00r7, 5.12), then the Linux and Mac
   siblings.
4. **Torque 3.x (#303).** Already default; the Debian lab check, the
   3.153 boot profile and 3D remain.

## 3. Switch a folder's default to its engine

Only after section 1b passes for that folder. One PR per folder (or a
small batch of siblings that passed together):

1. Make the no-argument path start the engine: the start screen hands
   the game over (`GQuattroPlay.pas` for Quattro, the `--engine` path made
   the default for the engine library, `graal304-torque` for Torque).
   Keep the Pascal path reachable (`GRAAL_PASCAL_GAME=1`, a missing engine
   binary, or no display). Never delete it.
2. Make the release ship the engine beside the program:
   `scripts/build.sh` copies it into the folder's build, and
   `scripts/release/pack.sh` packs it.
3. Rewrite the folder README's **Repro tracks** block: `default:` names
   the engine, `faithful engine:` says it is the no-argument path and
   links the e2e write-up, `relic / fallback:` names the Pascal track.
4. Add a `[x]` bullet under the next version in the folder's
   `RELEASE_NOTES.md`.
5. Tick the folder in #403 and say which e2e write-up proved it.
6. CI green (`loopback.sh` and `stress.sh` for that folder), then the PR
   goes to review.
