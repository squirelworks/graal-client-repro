# Assets: what each client opens, and the one assets zip

The original Graal files never go in this repository. A player keeps one
folder of them, `graal-assets/`, next to the rebuilt programs. This page
says how a program finds its files, what goes in the folder, and what each
client line's own install held.

## Layout: the programs in the root

```
<root>/
  Graal205(.exe)        every rebuilt client sits at the top
  Graal217(.exe)
  Graal222(.exe)
  Graal304              3.04 (Linux, as the original)
  graal-assets/         graal-assets.zip extracted here
    README.txt
    common/             byte for byte the same in every version that has it
    2.05r2/             one folder per version line, named by the build's
    2.22/               version label (ClientBuildLabel)
    3.04/
    4.04r2/  4.20r8/
    zelda-online1/
```

Nothing above the root is read. A real install dropped into the root, laid
out as the original had it (`levels/`, `sounds/`, ...), still wins over
`graal-assets/`.

## Search order

`common/GAssetDirs.pas` sets the folders; a file is taken from the first
that has it:

1. the data folder (the program's folder, or `--data DIR` when given);
2. `graal-assets/<version>/`, then each fallback version in the build's
   label;
3. `graal-assets/common/`;
4. else the build's built-in art (`common/builtin/`).

| Build | Label passed to `SetAssetRoots` | Version folders read |
|---|---|---|
| 2.05 rev 2 | `2.05r2` | `2.05r2/` |
| 2.05 | `2.05;2.05r2` | `2.05/` (none: the 2.05 archive holds only the exe), then `2.05r2/` |
| 2.05 rev 1 | `2.05r1;2.05r2` | `2.05r1/` (none: only the exe), then `2.05r2/` |
| 2.17.1 | `2.17.1;2.22` | `2.17.1/` (none shipped), then `2.22/`: 2.17.1 came in the same folder as 2.22 |
| 2.22 | `2.22` | `2.22/` |
| 3.04 | `3.04` | `3.04/` (the Linux install, `graal-decompile/torque/lin304`) |
| 4.04r2 (PR #35) | `4.04r2` | `4.04r2/` |
| 4.20r8 (PR #38) | `4.20r8` | `4.20r8/` |
| 4.20r6 (PR #40) | `4.20r6;4.20r8` | `4.20r6/` (none shipped), then `4.20r8/`: its install's files are 4.20r8's byte for byte |
| 1998-99 betas b1 to b15, b4a, b5a, b9a (PRs #51 to #69) | `bN` (own folder only) | `bN/` |
| Graal3D (PR #70) | `3d` | `3d/` |
| Zelda Online 1 (Java, `ZeldaOnline1.jar`) | its own `Assets` class, same order | `zelda-online1/` |

`--data DIR` today replaces the program's folder: with it, the root and a
`graal-assets/` beside the program are not read, only `DIR` (or
`DIR/graal-assets/`, or `DIR` itself when it is a `graal-assets` folder).

## What goes in the zip

Only what a rebuilt client opens. The rule, applied by
`scripts/assets/needed_assets.py`:

- **Everything under `levels/`, `sounds/` and `maps/`.** Levels, ganis,
  heads, bodies, swords, shields, hats, weapons, images, midis and sounds
  are looked up by the name a level, a script or the server gives, and the
  name may carry a sub folder (`baddies/x.gif`, `emoticons/y.mng`), which
  `levels/` is searched with. So the whole tree is reachable.
- **The files the code names at the top of a version folder:** `pics1`,
  `picso` (2.22 offline tiledef), `sprites`, `state`, `letters`,
  `bomb1`/`bomb2`, `body`, `head0`, `sword1`, `shield1`, the default
  weapon pictures, `arrays.dat`, `arrays2.dat` (2.22 listserver),
  `objects.dat` (the 2.05 rev 2 and 2.17.1 editors), `listserver.txt`,
  `start.nw`.
- **Map grids and their pictures:** `bigmap.txt`/`map.png`,
  `minimap.txt`/`map2.png`, `tutorialmap*`, and the grids `setmap` can
  name (`mappw`, `mapmantara`, `ccbig`, `ccsmall`).
- **The start-window art the start screens open:**
  `embedded/images/screenimg1.jpg`, `button1.bmp`, `button2.bmp`.
- **3.04's `license/license.graal`** (its listserver host and port).

**Start-window art belongs to its own version.** `embedded/images/` holds
the pictures taken out of one version's exe. A build may only draw start
art from its own version's folder, never through a fallback: the real
Graal 2.17.1 exe carries its own small 160x115 skin, not 2.22's 577x416
pictures. So 2.17.1 draws its built-in start screen unless
`graal-assets/2.17.1/embedded/images/` exists, even though it reads
`2.22/` for ordinary game files. (Graal217 on main opens no start art;
some start-screen branches list `embedded/images/...` through
`AssetPath`, which would follow the fallback to `2.22/`.)

Cut, because no rebuilt client opens them: readmes, `newfeatures*`,
`commands.rtf`, `npcprogramming.doc`, `DINPUTDLL-bug.txt`, language files,
`TEMPSITC.TTF`, `loadingscreen.jpg`, `headsconfig.txt`,
`servermessage.html`, `soundicon.png`, `opps.png`, the other resources
taken out of the exes (forms, cursors, icons, strings, `screenimg2.jpg`),
the 2.22 editor object sets (`tileobjects/`) and `new1.nw`. When a build
starts to open one of these, add it to `KEEP_TOP` / `KEEP_PATHS` in
`needed_assets.py` and cut the zip again.

**Version sets are never mixed.** A version folder holds that version's own
install. Where its install lacks something a build needs, the stand-in must
come from the same art generation and be written down in the zip's
README: `2.05r2/levels/ganis/` holds classic ganis (32 px body cells, from
the Graal NewMain 2.6 install) because the 2.05 rev 2 install has no
ganis; Graal NW ganis (36 px cells for the NW bodies) broke 2.05 bodies
and must not be used for the 2.0 line.

**Deduplication.** `merge_assets.py` moves a file to `common/` only when
every set has it, byte for byte, at the same path. Every build reads
`common/`, so a file shared by only some sets stays in their own folders;
in `common/` it would hand the other builds a file their install never
had. Today no file is in all four sets, so `common/` is empty (the 5
npc and weapon scripts 2.05 rev 2, 2.22 and 3.04 share stay in each). 2.22 and 3.04 share 110
files byte for byte (ganis, emoticons, smilies) that 2.05 rev 2 lacks;
they stay in both folders. The 2.05 rev 2 and 2.22 sets share almost
nothing byte for byte (2.22 re-saved its art). A version that
shipped with another version's files (2.17.1, 2.05, 2.05 rev 1) gets no
folder of its own and reads the other's through its label.

### Building the zip

```
# per-version sets, each laid out as next to its exe
scripts/assets/merge_assets.py /tmp/graal-assets 2.05r2=sets/2.05r2 2.22=sets/2.22
# cut to what the clients open, zip, list what was cut
scripts/assets/needed_assets.py /tmp/graal-assets graal-assets.zip \
    --readme README.txt --list cut.txt
```

The zip is deterministic (sorted names, fixed times) and extracts as
`graal-assets/`. It lives with Squirrel's project files, never here.

**The 1998-99 betas** keep their levels and the pictures their levels
name next to the exe (1st to 3rd Graal and the 4th alpha have no
`levels/` at all), and their builds look a name up in the folder and in
`levels/`. So a beta folder keeps `arrays.dat` and every level file
(`.graal`, `.zelda`, `.editor`, `.forest`) and picture (`.gif`, `.png`),
in `levels/` or at the top. Sounds, music (`.wav`, `.mid`) and `.lost`
files are cut: the beta builds play none. **Graal3D** keeps the 20
meshes and textures its build opens (`level1.x`, the body-part `.x`
files and the `.bmp` textures); `startlevel.x` is the server's.

**Fallback labels.** `needed_assets.py --fallback VERSION=OTHER` leaves
out of VERSION's folder what OTHER has byte for byte, for a build
labelled `VERSION;OTHER`. It refuses when OTHER has any file VERSION's
install lacks. The betas that qualify, one level deep: b12, b13, b14 and
b15 on b11 (b12's kept files are b11's exactly), and b8 on b7. With
those labels the zip goes from 35 MB to 23 MB; until the beta builds
carry them, every beta has its full folder.

### Known gaps

- No install in hand has 2.22's `arrays2.dat`; Graal222 falls back to
  `listserver.txt` in the root, else a listserver on this machine.
- The 2.05 rev 2 install lacks `gate1.gif` and `head495.gif`, which
  `tutorial_b-4` names; 2.22's lacks `g2k2master[0].gani` and
  `petzzz.mng`, which `offlinetutorial_b-2` names. Older installs have
  `gate1.gif` (`levels/gifs/`), but it is not copied across versions.
- 3.04 keeps its files where its install had them: `levels/tiles/pics1.png`
  and `picso.png`, `levels/images/sprites.png`, `state.png`, `bomb1/2.png`,
  `levels/letters/letters.png`, `levels/tutorial/offlinetutorial_*.graal`,
  and no `arrays.dat`. Graal304 on main looks for `pics1.png`, `picso.png`
  and the tutorial at the top and in `levels/`, so with only the zip it
  draws the built-in tiles and does not find Training; it needs the
  build to search 3.04's own folders.
- 4.04r2, 4.20r8 and 4.20r6 keep their tiles in `levels/tiles/` and the
  tutorial in `levels/tutorial/`, as 3.04 does, and ship no `arrays.dat`
  or `sprites.png`. The 4.x builds read `levels/tiles/`,
  `levels/tutorial/` and `levels/tiledefs/` (PRs #35, #38, #40).
- 2.17.1 reads 2.22's start-window art and has no `objects.dat` (2.22
  shipped `tileobjects/` instead), as the shared install had it.

## What each client line's install holds

Counted from the installs in `graal clients.zip` (project files). "Runtime"
is the install without programs, installers, docs, language files and
tool folders; it is what that line's folder would hold before the cut
above. "Same as previous" counts runtime files byte for byte equal at the
same path in the line before it, which says how much a fallback label
would save.

| Line | Install root holds | Runtime files | KB | Same as previous | Rebuilt |
|---|---|---:|---:|---:|---|
| 1st Graal (1998) | levels as `level*.graal`/`house*.graal` beside the exe; `pics1.gif`, `link.gif`, `letters.gif`, `state.gif`, `opps.gif`, `map.gif`, `arrays.dat`, `objects.dat` | 24 | 264 | 0 | **yes** (`b1/`) |
| 2nd Graal | `.zelda`/`.editor` levels and gifs beside the exe | 158 | 513 | 11 | **yes** (`b2/`) |
| 3rd Graal | as 2nd, plus `.graal` levels and `.WAV` sounds at the top | 262 | 864 | 117 | **yes** (`b3/`) |
| 4th alpha | as 3rd, `.forest` levels | 696 | 2162 | 170 | **yes** (`b4a/`) |
| 4th Graal | first `levels/` folder; `heads.gif` and gif sheets at the top | 267 | 871 | 4 | **yes** (`b4/`) |
| 5th alpha | top-level gif sheets only | 10 | 304 | 1 | **yes** (`b5a/`) |
| 5th Graal | `levels/`, `sounds/`, gif sheets (`pics1`, `sprites`, `state`, `letters`, `heads`, `opps`, `map`) | 719 | 2507 | 6 | **yes** (`b5/`) |
| 6th Graal | as 5th, `map2.gif` | 813 | 2878 | 47 | **yes** (`b6/`) |
| 7th Graal | as 6th | 1014 | 3443 | 651 | **yes** (`b7/`) |
| 8th Graal | as 7th | 1025 | 3370 | 1005 | **yes** (`b8/`) |
| 9th alpha | sheets only | 5 | 101 | 0 | **yes** (`b9a/`) |
| 9th Graal | sheets and `sounds/`, no levels | 39 | 797 | 4 | **yes** (`b9/`) |
| 10th Graal | as 8th | 1538 | 5803 | 36 | **yes** (`b10/`) |
| 11th to 14th | as 10th | 1557 | 5945 | 1499 to 1557 | **yes** (`b11/` `b12/` `b13/` `b14/`) |
| 15th Graal | as 14th, `map3.gif` | 1741 | 6962 | 1530 | **yes** (`b15/`) |
| 1.1 / 1.1.9 | as 15th | 1643 | 5065 | 1503 / 1641 | no |
| 1.21 | InstallShield setup only, not unpacked | 0 | 0 | | no |
| 1.28b2, 1.3 test, 1.31, 1.32 | gif sheets; `bigmap.txt`, `minimap.txt`, `zeldamap.txt`, `ccbig`/`ccsmall` | 435 to 440 | 1800 | 434 to 435 | no |
| 1.33 to 1.39 | first png sheets (`pics1.png`, `body.png`, `bomb1/2.png`), `mappw`, `mapmantara` (1.37 on) | 157 to 441 | 975 to 1652 | 152 to 429 | no |
| 1.41r1 | as 1.39, `body2/3.png`, `weblevels/` | 203 | 1083 | 174 | no |
| NewMain 2.4 / 2.6 | `maps/`, `body4.png`, `light2.png`, `npmap*.png`; first `levels/ganis` | 93 / 142 | 780 / 1294 | 0 / 92 | no |
| 2.1 test 2 / 3 | `levels/` (npcs, smilies, webgifs), `maps/`, `state.png` | 5 / 24 | 262 / 284 | 0 / 4 | no |
| 2.0 to 2.05 rev 1 | the exe only (shipped as updates over a 2.0x install) | 0 | 0 | | 2.05, 2.05r1 in flight |
| 2.05 rev 2 | full install: png sheets, `levels/` (no `ganis/`), `sounds/`, `maps/`, map grids | 210 | 1395 | | **yes** (`2.05r2/`) |
| NW beta 1 / 2 | `arraysnw.dat`, `fbodynw.png`, region level folders, NW ganis (36 px) | 1862 / 1488 | 19711 / 16334 | 5 / 1473 | no |
| 2.17.1 | shipped inside the 2.22 folder | | | | **yes** (reads `2.22/`) |
| 2.22 | full install: `picso.png`, `levels/` with ganis, bomys, emoticons, midis, offline tutorial (from `graal-delphi-assets/2.22-src`, not in `graal clients.zip`) | 732 | 10348 | | **yes** (`2.22/`) |
| 2.3, 2.31 | install not in project files | | | | no |
| 3.04 (Linux) | Torque install (`graal-decompile/torque/lin304`, from Drive "Graal v3.04[Linux][Obsolete].sh"): `levels/` with `tiles/`, `tutorial/`, `images/`; `sounds/`, `maps/`, `license/`; Torque scripts in `common/`, `graaldata/` (cut) | 414 | 5600 | 110 same as 2.22 | **yes** (`3.04/`) |
| 4.04r2 | thin Windows install, dumped from its Thinstall package (`graal-decompile/unpacked-installers/4.04r2/files`): `levels/` (`tiles/`, `tutorial/`, `ganis/`, `images/`, heads, bodies), `levels3d/` GUI, `languages3D/`, `license/`, `sounds/` | 131 | | | **yes** (`4.04r2/`, 68 kept) |
| 4.20r8 | Linux installer 4.208 (Drive "Graal v4.20r8[Linux][Installer].bin", autopackage; laid out by its install script). The Windows "Unpacked" 7z on Drive is password-protected | 130 | | | **yes** (`4.20r8/`, 69 kept) |
| 4.20r6 | Linux installer 4.206 (Drive "Graal v4.20r6[Linux][Installer][2007-01-10].bin"); the rebuild is of the Mac 4.20r6, whose dmg is not unpacked. Same files as 4.20r8 byte for byte except `license/sig.graal` | 130 | | | **yes** (reads `4.20r8/`) |
| 3.153 (Mac) | install in `graal-decompile/torque/mac3153`; not inventoried until a build lands | | | | no |
| 5.x, 6.x | unpacked Windows clients in `graal-decompile/unpacked-installers/` (5.12 to 6.03r7) | | | | 5.00r7 in flight (PR #39) |
| Graal3D (2000) | DirectX `.x` meshes and `.bmp` textures at the top | 21 | 455 | | **yes** (`3d/`) |
| Zelda Online 1 | applet: `pics1.gif`, `arrays.dat`, 36 `level*.zelda` (`Z3-V1.03`), `link.gif`, `state.gif`, `hit.au`, classes (from Drive `zeldaonline1.7z`) | 38 kept | 130 | | **yes** (`zelda-online1/`: `pics1.gif`, `arrays.dat`, `levels/*.zelda`) |
| Zelda Online 2 | Java classes and levels under `game/` (author source alongside: never copied) | 90 | 535 | | no |
| Java Graal, Game Boy demo | not in `graal clients.zip` (`javagraal_rip.rar`, `graalgb.rar` on Drive) | | | | no |

When a new build lands, its thread lists the files its build opens; its
line's install goes through `merge_assets.py` and `needed_assets.py`, and
the zip gains one folder. A line that shipped as an update over another
line's install (2.0 to 2.05 rev 1) gets a fallback label instead of a
folder. Lines whose installs are byte for byte near-identical (11th to
14th, 1.1 and 1.1.9, 1.28b2 to 1.32) can share a folder through a label,
but only when every file in the fallback folder is also in the build's
own install, byte for byte or overridden in its own folder: a fallback
must never hand a build a file its own install did not have.
