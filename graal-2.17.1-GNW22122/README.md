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
| NPC props read | `version-profiles/plo-npcprops-layouts.tsv`, `protocol/player-props.md` |
| Listserver port | `protocol/public-listserver-2026-10-25.md`, `protocol/login-frames-by-version-2026-10-25.md` |
| 2.1 to 2.17 features | `client-internals/feature-timeline.md`, `formats/gani.txt` |
| Everything inherited | the sources listed in the [2.05 rev 2 README](../graal-2.05r2-GNW03081/README.md) |

## Units

| Unit | What |
|---|---|
| `src/Graal217.dpr` | the program: start screen, flags, the run loop, the editor entry |
| `src/Protocol217.pas` | message ids and prop ids as 2.17.1 knows them |
| `src/GraalClient.pas` | the gen-3 link, login with the tamper check |
| `src/Adventure.pas` | the game: level, players, props, walking, items, combat, drawing |
| `src/Npc217.pas`, `src/NpcBridge217.pas` | level NPCs and their GS1 scripts, and how they reach the game |
| `src/Baddy217.pas` | baddies |
| `src/Sound217.pas`, `src/Map217.pas` | sound effects, the big map and the minimap |
| `src/editor/` | the built-in level editor (F4) |
| `src/StartScreen217.pas` | the 2.17 listserver step on the shared start screen |
| `../common/GGs1.pas` | the GS1 language, shared with 2.05 rev 2 |

The NPC, baddy, sound, map and editor units are copies of the 2.05 rev 2
ones (renamed `*217`), so a fix to one build does not move the other.
They change here only where 2.17.1 is known to differ.

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
  it; with neither, `listserver.graal.in:14923`. That is the public
  listserver's legacy port: 2.17.1's list login is the classic plain
  frame, which 14923 answers and 14922 (the supported port, for the gen-5
  login of 2.22 and later) leaves unanswered. Training starts at
  `offlinetutorial_b-2.graal` when it lies next to the program, else at the
  built-in `start.nw`. The built-in original assets fill in for anything
  not on disk (tests).
- Loopback: two 2.17.1 clients log into seihai-gserver, see each other and
  walk through a link (`scripts/loopback.sh`, run in CI).

## From 2.05 rev 2 (done)

Everything the 2.05 rev 2 rebuild plays, on 2.17.1's wire: the sword, lift
and throw, chests, floor items, signs, weapons with the bow and the Q item
list, bombs, being hurt, dying and respawning, level NPCs running GS1,
baddies, sound effects, the big map and minimap, and the F4 level editor
(`Graal217 FILE.graal` opens a level in it). Their tests run here too
(`tests/Test217.dpr`, `TestNpc217.pas`, `TestBaddy217.pas`,
`TestEditor217.dpr`, `TestSoundMap217.dpr`), built with the heap tracer.

Where 2.05 reads another player's sword swing from the sprite prop
(sprites 6 to 10), 2.17.1 has the pose in the GANI prop, so a swing is
another player in the `sword` gani [inf].

## 2.1 to 2.17 features (done)

Found by playing the offline tutorial that ships in the 2.17.1 folder with
the original files (2.22's `levels/`), and checked against the frames the
2.22 rebuild draws:

- `addtiledef IMAGE,PREFIX`: levels whose name starts with PREFIX are
  drawn from IMAGE instead of pics1 (the tutorial uses `picso.png`).
- `replaceani OLD,NEW`: the player's own OLD gani is played, and sent as
  the GANI prop, as NEW (the tutorial's `human2_*` set).
- Gani attributes `#P1` to `#P30`: the player's props 37 to 41, 46 to 49
  and 54 to 74 are kept, `setplayerprop #Pn` sets them, and a gani's
  `ATTRn` draws them. Attribute pictures are also looked for in
  `levels/webgifs/` and the other picture folders of the install.
- `ATTACHSPRITE` and `ATTACHSPRITE2` in ganis (common `GAni.pas`): the
  tutorial character's hair, arms and legs hang on the head and body.
- NPC props: the stream reads 0 to 40, 44 to 47 and 53 to 73 and stops at
  41 to 43 and 48 to 52, as 2.17.1's switch does.
- A gani that is not on disk is not drawn (it would be downloaded online);
  the outline marker is drawn only when there are no ganis at all.

## Not yet

- Which ids other players' prop stream stops at was not isolated in the
  notes; it takes the same range as the own stream here [inf].
- Gmaps, the ids 169 to 185 (ghost mode, server maps, serverwarp, RPG
  window, status list, process list, screenshots, level heights), large
  file downloads.
- The `arrays2.sig` check of `arrays2.dat`.
- The arrival point on `offlinetutorial_b-2.graal` (30, 30 is a guess).
- `addtiledef2`, `replaceani` for other players' NPC characters, gani
  scripts (`SCRIPT ... SCRIPTEND`), string arrays, `play2`, `showimg2`,
  `seteffectmode` and the rest of the GS1 2.1 to 2.17 added: the GS1 table
  is still 2.05's.
- A side-by-side check with the real 2.17.1 under Wine.
- Chat-line emoticons and the rest of what 2.17.1 added over 2.05.
- The link test point was measured on 2.05, not on 2.17.1.
- Everything listed under "Not yet" for 2.05.

## Build and run

As for 2.05: `scripts/build.sh graal-2.17.1-GNW22122`, `scripts/test.sh`,
then `Graal217` with no arguments for the start screen, or with the same
flags as `Graal205`. A 2.2.2-era install
(with `levels/ganis`) works as `--data`.
