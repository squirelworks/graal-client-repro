# Graal 2.22 (`GNW03014`)

The 2.22 client, rebuilt. Original: `Graal_222.exe` from the Graal Reborn
2.2.2.0 folder, a Delphi build like 2.05 with the same network classes. It
is the first build here on the gen-5 wire (login type 5, a compression byte
per frame, partial XOR both ways) and the first with gmaps.

## Sources

Everything here is written from the notes in
[graal_analysis](https://github.com/squirelworks/graal_analysis) and from
captures of the real 2.22 client, not from decompiled code:

| Area | Notes |
|---|---|
| Login line, token, login type | `protocol/client-versions.md`, `client-internals/version-tokens.md` |
| Gen-5 frames, XOR groups, compression choice | `protocol/codec-and-framing.md` ("Gen 4/5 partial XOR"), `protocol/client-versions.md` ("Gen-5 send on the client") |
| Tamper check (39) | `version-profiles/tampercheck-values.tsv`, `client-internals/decomp-findings-2026-10-24-b/01-tamper-check-id39.md` |
| Ids handled and sent | `version-profiles/2.22-2.31.md`, `protocol/packet-ids.md`, `version-profiles/plo-layouts-217-231.tsv` |
| Player props (2.1+ forms, 2.22 parser sets) | `protocol/player-props.md`, `version-profiles/plo-playerprops-layouts.tsv`, `plo-otherplprops-layouts.tsv` |
| Level links | `version-profiles/plo-levellink-layouts.tsv` |
| Level changes, 39 after a warp, 24, 178 | `client-internals/decomp-findings-2026-10-24-b/08-lab-findings-levelchange-24-178.md` |
| Gmaps and edge crossings | `formats/gmap.md`, `client-internals/feature-specs/06-gmap-overworld.md` |
| Walking, link point | `client-internals/decomp-findings-2026-10-25-m/01-walking-rule.md` (2.05), checked against run-222d |
| First client frame, walk props | the b4_222 capture (graal-decompile/live-trace/item-drops), decode-222-a-b, run-222d |

## Units

| Unit | What it does |
|---|---|
| `../common/GBzip2.pas` | bzip2 in and out (new, shared: 2.31 needs it too) |
| `src/Protocol222.pas` | ids, token, tamper bytes, gen-5 constants, the 80 handled ids |
| `src/GraalClient.pas` | `TGraalClient` (socket, out buffer, frames) and `TAdventureClient` (gen-5 codec, login) |
| `src/Adventure.pas` | `TAdventure`: game state, level cache, gmaps, message handlers, 50 ms tick, drawing |
| `src/Graal222.dpr` | front end: the start screen with no arguments; flags for the window, scripted keys, frame dump, stress runs |
| `src/ListServer222.pas` | the 2.22 listserver step and `arrays2.dat` |
| `src/StartScreen222.pas` | what 2.22 plugs into the shared start screen (`../common/GStartScreen.pas`): list step, fallback hosts, start-window art, character |
| `src/RunMode.pas` | stress-run support (the same as 2.05's) |
| `../common/GGs1.pas` | the GS1 script engine, shared with 2.05 rev 2 and 2.17.1; 2.22's own additions are not in yet |
| `src/Npc222.pas`, `src/NpcBridge222.pas` | level NPCs and what their scripts reach in the game (copies of 2.05's) |
| `src/Baddy222.pas` | baddies, by the 2.22 spec (client-internals/baddies-222.md in Graal_analysis) |
| `src/Sound222.pas` | the sounds the game plays by itself (gani `PLAYSOUND`), through `common/GSound.pas` |
| `src/Map222.pas` | the big map on M and the minimap, from the install's `maps/` |
| `src/Terrain222.pas` | the height-shaped ground of new-world maps: the gmaps' `HEIGHTS` grids, and tile 0 drawn as water, sand or grass by height, lit by slope |

## What works

- **A GUI program**, as `Graal_222.exe` was. Started with no arguments it
  opens the shared start screen (`common/GStartScreen.pas`): a nick name,
  Training, Options and Start. On Windows it is a windowed program with no
  console. Flags still run it from the command line (stress runs, CI).
- **Training** starts the offline tutorial `Graal_222.exe` carried in its
  resources (`offlinetutorial_b-2.graal`, the centre of nine levels) when
  it lies next to the program, else the built-in starter level.
- **Built-in assets**: the program carries small original defaults (tile
  sheet, body, head, ganis, two levels; `common/builtin/`), so it runs
  with nothing next to it. Files from a 2.22 install next to it, or under
  `--data`, replace them in the game. The start screen is always this
  project's own; the original start window is not drawn.
  The shared `graal-assets/` folder inside the program's folder works too: `graal-assets/2.22/`, then `graal-assets/common/`
  (`common/GAssetDirs.pas`).
- **The listserver step**: hosts from `arrays2.dat` (line 0, then the
  fallbacks on lines 5 and 6), `listserver.txt` next to the program wins
  over it, and with neither it asks `listserver.graal.in` on port 14922
  (the original pointed at GraalOnline's listserver); id 7 (key, `GNW30123`, `newmain`) in a plain zlib frame, then
  id 1 (account, password) in gen 5; the list (id 0), status (2), site (3),
  error (4) and upgrade (5) lines back (tests; tried against a stand-in
  2.22 listserver and then seihai-gserver on a virtual screen).
- **addtiledef**: the one GS1 line read without a script engine. A level
  script's `addtiledef IMAGE,PREFIX` swaps the tile sheet for levels whose
  name starts with PREFIX, which is how the tutorial gets `picso.png`.
- **Login** as 2.22 sends it: type 5, the key, `GNW03014`, account,
  password, in a frame of its own (zlib, no compression byte, no XOR). Then
  `PLI_LANGUAGE` and `PLI_TAMPERCHECK` (`250e4d0f962b03ede631`) in the next
  frame, which is byte for byte the real client's (test).
- **Gen-5 frames** both ways: compression byte 2 (raw), 4 (zlib) or 6
  (bz2), chosen as 2.22 chooses; XOR of one LCG step per 4-byte group, at
  most 12 groups raw or 4 compressed, own iterator per direction. Checked
  on 12 frames the real client sent (every uncompressed one is re-made byte
  for byte, the compression byte matches on all) and the real server's
  first 8 frames, one of them bz2 (tests).
- **bzip2** written out in Pascal (`common/GBzip2.pas`), since neither
  Delphi 5 nor Free Pascal has an encoder. Checked against Python's bz2
  both ways and on the captured bz2 frame.
- **The receive switch** has the 80 ids 2.22 handles; every other id is
  ignored silently, as 2.22 does (82, 190 and 194 from a real server are
  tested).
- **Props** in the 2.1 forms: GANI as a string, sword and shield with
  images, OSTYPE (75), TEXTCODEPAGE (76), GMAPLEVELX / Y, Z. The own
  stream stops at 50, 51, 53 and above 74; the other-player stream at 1,
  3 to 7, 14, 22, 25 to 29 and above 76, as 2.22's parsers do (tests).
- **The first frame after the login burst**: `PLI_UPDATEFILE` for the four
  player-list icons, `ADJACENTLEVEL` on a gmap, then the props 0, 11, 13,
  18, 31, 33, 52, 75, 76. The props message is byte for byte the real one
  (test).
- **Walking** with the 2.05 rule (half-tile steps, six probes, the corner
  nudge), which matches run-222d. Props go out every other tick: GANI
  (`walk`, `idle`), X and Y as half tiles, SPRITE (the direction) when it
  turns.
- **Levels**: a cache of every level seen in the session, with its mod
  time. A link asks with `PLI_LEVELWARP` the first time and with
  `PLI_LEVELWARPMOD` (mod time first) once the level is held, and the
  tamper check follows in the same frame, as 2.22 does. A cached answer
  (no board) still lands the player (tests).
- **Gmaps**: `PLO_PLAYERWARP2`, the `.gmap` from the install or by
  `WANTFILE` / `PLO_FILE`, `ADJACENTLEVEL` for the 3x3 neighbourhood,
  neighbours' data kept apart from the player's level, the world drawn
  across cells, and walking over an edge: the wrapped position and the new
  cell prop go in one props message, with a fresh tamper check (tests).
  Offline, `--level some.gmap` plays a gmap from its folder.
- `PLO_BOARDMODIFY` and `PLO_BOARDMODIFY2`, freeze and unfreeze,
  `PLO_SIGNATURE`, `PLO_SERVERWARP` (reconnects with a new key, same
  account), `PLI_SHOWIMG` = 9 every 5.1 s while another player is in the
  level.
- Loopback: two clients log into seihai-gserver, load the board and walk;
  the second sees the first; one walks through a level link
  (`scripts/loopback.sh`, run in CI for every build).

## Play, carried over from 2.05

The game layer of the 2.05 rev 2 rebuild runs in 2.22 too, in 2.22's own
copies of its units (the repo's rule for `common/`). What each part does,
and which notes it comes from, is in the 2.05 README; here it runs on the
2.22 wire and on gmaps. None of it has been checked side by side with the
real 2.22 yet beyond the offline tutorial.

- **Actions**: S swings the sword and cuts bushes; A lifts, carries,
  throws and opens chests; items on the floor are taken by walking over
  them (`PLI_ITEMTAKE`).
- **Combat**: hurt, knockback, death and respawn; other players' swings
  are judged on their `sword` gani (2.1 and later send GANI) or on the
  classic sword sprites; bombs and explosions both ways.
- **The status display**: A/S/D buttons, rupees, bombs, arrows, hearts and
  the alignment bar, from the install's `state.png`.
- **Signs**, **weapons** (the weapon list, D, shots, the Q item list),
  `PLO_DEFAULTWEAPON`, `PLO_NPCWEAPONADD`, `PLO_NPCWEAPONDEL`.
- **Level NPCs and GS1**: offline, a level's NPCs and baddies start when
  the player enters it (the offline tutorial's teacher, palm trees and
  cauldron show and run their scripts); online they come from the server
  (`PLO_NPCPROPS`, `PLO_BADDYPROPS`). NPC pictures are found in the
  install's `levels/webgifs`, `npcs`, `images`, `tiledefs` and the other
  level folders.
- **Sound effects** (window only, `--nosound` turns them off) and the
  **maps** (M for the big map, the minimap bottom left).
- On a gmap, all of this lives in the player's current cell: it is drawn in
  that cell's place, and crossing an edge, a warp or a link clears it.

Keys: arrows or I/J/K/L walk, S sword, A lift / throw / open, D weapon,
Q item list, M map, Esc leaves. `--keys` takes `a`, `s`, `d` and `q` too.

## Stress runs (phase 4)

The same flags as 2.05 (`--headless`, `--seconds`, `--walk random`,
`--link-every`, `--stats-every`, JSON summary, exit codes; see the 2.05
README). 50 headless 2.22 clients on one seihai-gserver for 40 s, all in
one level, walking at random and taking a link every 3 s: all 50 ended
clean, 1616 of 1619 link warps went through (the rest were cut off at the
end), tick p99 at most 0.72 ms, about 4.8 MB each (5.3 MB peak).

Hardening checks, all in CI:

- The test program is built with range and overflow checks and the heap
  tracer; `scripts/test.sh` fails on any unfreed memory.
- A fuzz test sends 20000 random and mangled messages (gmap names,
  `PLAYERWARP2`, `FILE` with broken gmaps, `BOARDMODIFY2`, `SERVERWARP`)
  and 3000 random gen-5 frames through the receive path.
- bzip2 input is capped at the 16 MB frame limit and its CRCs are checked;
  a bad frame, an unknown compression byte or an unfinished message over
  4 MB drops the link.

After the play layer came in (2026-11-04): 20 headless 2.22 clients on
one seihai-gserver for 20 s, walking at random and taking a link every
3 s: all 20 ended clean, 368 of 368 link warps went through, tick p99 at
most 0.76 ms, 18 MB peak each.

## Checked against the real 2.22

The real `Graal_222.exe` (Graal Reborn 2.22.0 folder) runs under Wine in a
network namespace with only loopback. Training side by side with the
rebuild on the same files (`--data` pointed at that folder):

- The same level, path and NPC places: palm trees, cauldron, teacher and
  torches stand where the real client draws them.
- Different, not done yet:
  - the ground: the tutorial's levels have height grids (the `HEIGHTS`
    blocks of `maps/offlinetutorial.gmap`), and the real client draws
    their tile 0 as ground picked by height. The rebuild now does too
    (`Terrain222`), from what was measured by setting the grid to one
    height at a time under Wine: water below 0, sand to about 3, sand and
    grass mixed about 4, grass above, flat ground about 30 darker than
    `picso.png` and slopes lit from the upper left. Side by side it is
    close but not the same: the real one blends heights with a seeded
    displacement and its grass has lighter patches;
  - the player: the tutorial dresses the player with
    `setplayerprop #P1..#P6` and `replaceani idle,human2_idle` (hair, legs,
    arms on the human2 ganis); the rebuild skips both and draws the
    default character, bald because `khairs0.png` is not in the folder;
  - the torches' light and the darker night look, the teacher's "Touch to
    get information" text (its gani attribute), and the chat bar under
    the game (the real game view is 640 x 456 above it);
- Where Training puts the player: the real one starts just below the
  cauldron; the rebuild now starts at (27.5, 31.5), matched by eye (the
  earlier guess, (30, 30), stood inside the cauldron).

## Owner decisions

- `NEEDS OWNER DECISION`: the real 2.22 answers `PLO_LISTPROCESSES` (182)
  with the programs running on the player's machine. The rebuild sends
  only its own file name (`Adventure.pas`, `PLO_LISTPROCESSES`).

## Not yet, or not known

- `PLI_SHOWIMG` (24): the lab saw 2.22 send it only with another player in
  the level (0 in three solo sessions), but the b4_222 capture has a solo
  2.22 sending it at login and every 5.1 s. The condition is open; the
  rebuild follows the lab.
- The `gr.x` / `gr.y` flag sets come from the server's movement weapon
  script, which needs the GS1 engine; they are not sent.
- The gmap's outer edge and cells whose level has not arrived are walls;
  not measured.
- The early-flush size of the out buffer (60000 here, so a raw body fits
  the u16 length) is not traced; nor is `TCP_NODELAY`.
- The GS1 additions of 2.22 (gravity, textwidth, isthisflagset, ...),
  the 2.22 NPC props past 40 (`plo-npcprops-layouts.tsv`: 44 to 47 and
  53 to 73), NPCs in gmap cells other than the player's, the built-in
  editors (F4 / F6), chat bubbles and names.
- The 2.22 status display's sword and glove pictures beside S and A, and
  the chat bar under the game (the real 2.22 draws both).
- Files other than `.gmap` are not saved; `LARGEFILESTART` / `END`.
- `arrays2.sig` is not checked; the original start window's buttons
  (`button1-4.bmp`) are not used (the shared screen draws its own);
  Options, UDP peer traffic, voice chat.
- Where Training puts the player on `offlinetutorial_b-2.graal` is not
  traced: (27.5, 31.5), below the cauldron, is matched by eye to the real
  client (see above). The tutorial's script lines the engine does not
  model yet (`setplayerprop #P1..#P6`, `replaceani`, `loadmap`,
  `setletters`) are logged and skipped.
- A macOS window (headless or `--dump` there, as for 2.05).
