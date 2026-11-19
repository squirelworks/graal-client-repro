# The art the programs carry

Every rebuild runs on its own with nothing beside it. What it shows before
the player adds anything is graal-delphi's own art, in two sets:

- **The game art** (tiles, player, sprites, HUD, letters, ganis, a starter
  level), `common/builtin/`, drawn by `scripts/builtin/make_builtin.py`
  and compiled in as `common/GBuiltin.pas`. It follows the cell layout the
  clients expect (16 px tiles, 32 px body cells), so a real install's
  files replace it.
- **The program art**: what each original program carried in its own
  resources (start and server list backgrounds, picture buttons, the
  pictures inside its dialogs and toolbars, its icon and cursors, the
  Training and start levels). Each build keeps these in the shape its
  original had them, under the same names, so the code that lays out the
  start window, the server list and Training is unchanged. The pixels and
  boards are drawn by `scripts/art/make_art.py`.

The original program's own files are never committed. A player who owns
them puts them in `assets/` beside the program, and they win over both
sets with no rebuild ([assets.md](assets.md), "Your own files").

## How the program art is made

```
python3 -I scripts/art/make_art.py           # redraw every carried resource in place
python3 -I scripts/art/make_art.py --check   # exit 1 if any is not our art (CI)
python3 -I scripts/art/hook_res.py --check   # every resource unit asks assets/ first (CI)
```

`make_art.py` finds each resource wherever a build keeps it
(`scripts/art/containers.py`): files under `<build>/res/` and
`<build>/src/res/`, the generated `Res*.pas`, `RealRes*.pas` and
`ResGraal*.pas` units and `common/GRes20x.pas` (as byte arrays, hex or
base64 strings), the `.res` files the programs link, and the program icons
in `src/`. It works out what each one is from its name and shape, draws a
new one, and writes it back in the same place and format. Only the shape
of the old file is kept:

| Kept from the old file | Why |
|---|---|
| format (JPEG, BMP, PNG, GIF, ICO, CUR, GR-V / GLEVNW01 level) | the loaders are per format |
| width and height | the start windows and forms are laid out to them |
| bit depth, palette size, row order, BMP header kind | the BMP readers and the VCL glyph code |
| a VCL glyph's transparent colour (its bottom-left pixel) | that pixel names the colour drawn see-through |
| icon sizes and depths, cursor hot spots | Windows reads them |
| the piece rectangles of a Torque bitmap array (4.04r2 `DEFAULT*`) | the GUI cuts the pieces at those places |
| a level's links | Training and the start level are walked through them |

Everything else is new: pixels are drawn with shapes, the project's 5x7
pixel font (`scripts/builtin/font5x7.py`) and tiles of the project's own
tile sheet (`common/builtin/pics1.png`). The mascot is the Seihai
squirrel and its acorn (seihai-core 0.1.9), drawn again with shapes.
Running the script on its own output gives the same bytes, which is what
`--check` tests. Pillow is pinned in CI so JPEG and PNG bytes stay the
same.

When a resource is taken out of a real program (`scripts/res/*.py`,
`scripts/res20x/make_res20x.py`, `scripts/realres/extract_res.py`), the
extractor says to run `make_art.py` before committing. Those extractors
are also the way to fill `assets/` with a program's own files.

## What each resource is, and what it is now

| Resource | What the original showed | Now |
|---|---|---|
| `SCREENIMG1` (2.0x 476 x 330, 2.1x to 2.31 577 x 416) | start window background with the title art | a meadow of the project's tiles, darkened, with a "GRAAL-DELPHI" title band |
| `SCREENIMG2` | server list background with a panel for the list | the same meadow with a see-through panel |
| `LOADINGSCREEN` | loading picture | meadow, title, "Loading" |
| `STARTIMAGE` (Graal3D) | wooden login board with five labelled fields | a wooden board with the five labels and fields at the places `Connect3D` uses |
| `GRAALV4SCREEN`, `GRAALV4TITLE` (4.04r2) | start backdrop and title logo | meadow with a panel; an acorn and title on a see-through ground |
| `DEFAULTCHECK`, `DEFAULTRADIO`, `DEFAULTTEXTEDIT`, `DEFAULTSCROLL` (4.04r2) | Torque GUI skin pieces | new check boxes, radio buttons, text box frame and scroll parts in the same piece rectangles |
| `BUTTON1` to `BUTTON3`, server list `Button1` / `PaintButton1`, Help window buttons | picture buttons, up half and pressed half | moss-green bevelled bars, up and pressed |
| `BUTTON4`, server list `SpeedButton2` | the "GO" button, up and pressed | a "GO" button, up and pressed |
| `OPENGLYPH` | the Open button's glyph | a folder |
| `MAINICON` (`src/<Program>.ico`, `icon-MAINICON.ico`) | the program icon | an acorn |
| `cursor-32761` to `32767` | the VCL's hand, wait, multi-drag, split and no-drop cursors | the same seven kinds, drawn anew, hot spots kept |
| `TUTORIALA1` to `TUTORIALC3`, `ONLINESTARTLEVEL` | Training and online start levels | a new meadow per level with paths to each of the old links, one sign of our own; no NPCs, baddies or chests |
| Pictures inside forms (`Glyph.Data`, `Picture.Data`) | see below | see below |

Pictures inside the forms, by form and component (`GLYPHS` and `VERBS`
in `make_art.py`; a glyph twice as wide as high holds an up and a
disabled state, and gets both):

| Form | Components | Now |
|---|---|---|
| `TADVENTURE` (game window toolbar) | new, open, save, cut, copy, paste, play, enter, export, next, paint, tiles, delete, lamp | a page, folder, disk, scissors, copy, paste, play arrow, door arrow, export page, arrow, brush, tile grid, red cross, lamp |
| `TCONNECTFRAME` (1.x and beta start dialog) | credit pictures, a trophy, a character drawing | a "GRAAL-DELPHI / A FAN REBUILD" card with an acorn, a gold cup, the squirrel |
| `TCONTROLSFRAME` | keyboard, joystick, the player in each direction | a keyboard, a joystick, the built-in player |
| `TOPTIONS` | two level screenshots | two small meadows |
| `TSERVERMESSAGE` | back, forward, close, refresh, home | the same five symbols |
| `TRECONNECTFRAME`, `TLINKOPTIONS`, `TPERSONACTION`, `TEDITPERSON`, `TWAABOUT` | warning, link, sign, test, lamp, about | warning sign, green arrow, sign post, refresh, lamp, acorn |
| any other form | Delete / Remove, Load / Open, Save, Edit, Close buttons | a red cross, folder, disk, edit page, red cross |

## What stays as it was

- **Text**: the forms' layout and captions, the string tables
  (`strings.txt`), the character lists (`characters.txt`,
  `HEADSCONFIG`), the 2.22 English language file, and Delphi's own
  `DVCLAL` / `PACKAGEINFO`. They are what the programs read to behave like
  the originals (tests check some of them), not pictures. Whether to
  rewrite them is open.
- **Version info and manifests** in `src/<Program>.rc` are the project's
  own (`scripts/win/make_winres.py`).

## What was removed

The whole-install packs some builds carried (`src/res/<Program>Install.res`
for 2.1t2, 2.1t3, 2.1.0.0, 2.17.1, NewMain 2.4 and 2.6, the NewWorld betas,
and the install part of 2.22's `Res222.pas` with `res/install/`: levels,
ganis, heads, bodies, sounds, MIDI, language files and the Tempus Sans
font, about 30 MB) are gone. Those files are game data from an install;
they now come from `assets/`, `graal-assets/` or the built-in art like
every other build's. `scripts/res/install_res.py` still packs an install
into a `.res` for a private build; such a pack is not committed.

The git history still holds the earlier files.

## What it looks like

![Start and server list backgrounds, the Graal3D login board, the 4.04r2
backdrop, picture buttons, GUI skin pieces, form pictures and toolbar
glyphs, all drawn by make_art.py](art/samples.png)

`docs/art/samples.png` shows only the project's own art (from the files in
the repository after `make_art.py`).
