# gui

**Patched.** The classes are stock TGE (`GuiCanvas`, `GuiControl`, the stock controls, profiles, themes). From the 4.x/5.0 2D engine onward the canvas does not draw pixels itself: each draw goes through the host pointer installed by `graal_set…`, and an empty pointer does nothing. 3.04 still draws through Torque's own OpenGL device. One unit covers both; the hybrid host is why the kind is patched rather than stock.

What it has to do later: build the control tree the shipped 3.04 scripts create, and on the hybrid engine host the same class names while the launcher or the 3D DLL supplies pixels. `GuiGraalCtrl` and `GuiGraal3DCtrl` are `guigraal`. The 4.2.0.8 script builder discards those two names so script does not construct them; that rule lives with `guigraal`.

Stock classes the 3.04 scripts actually construct include `GuiTextCtrl`, `GuiButtonCtrl`, `GuiControlProfile`, `GuiControl`, `GuiTextEditCtrl`, `GuiScrollCtrl`, `GuiWindowCtrl`, `GuiCheckBoxCtrl`, `GuiPopUpMenuCtrl`, `GuiTextListCtrl`, `GuiMLTextCtrl`, `GuiSliderCtrl`, `GuiChunkedBitmapCtrl`, plus the console, inspector, tree and editor controls named in `torque/study-torque-clients.md`.

| Version | Linked? |
|---|---|
| 3.04 | Yes. Canvas, themes, `.gft` fonts. Scripts call `Canvas.setContent`. |
| 3.153 | Yes. |
| 4.04r2 3D | Yes. `GuiCanvas` and `GuiControl` are in that DLL. |
| 4.2.0.8 launcher | No. The launcher calls `renderGraalCanvas` and draws with DirectDraw. |
| 4.2.0.8 engine | Yes. `GuiCanvas` is the screen object (`renderFrame`, `setContentControl`, input). `Point2I` is `math`. |
| 4.2.0.8 3D | Yes. `GuiCanvas::setContentControl` installs `GUIContainer3D`. |
| 5.0.0.7 launcher | No. The note says `GuiCanvas` is absent from the exe. |
| 5.0.0.7 engine | Yes. `GuiCanvas`, `GuiControl`, `GuiScrollCtrl`, `GuiWindowCtrl`, `GuiControlProfile`. |
| 5.0.0.7 3D | Yes. `GuiCanvas` (`setContentControl`, `paint`, `mouseLock`, `showHint`). |
| 5.30 / 5.31 | Residual names, not this unit. `GuiCanvas` is absent. `GuiControl` and, in 5.31, the longer `Gui*` list remain, with Torque field names (`horizSizing`, `vertSizing`, `fillColor`, `makeFirstResponder`). |
| 6.x | Residual names, not this unit. Unpacked 6.00 reimplements the GS2 control vocabulary. `GuiGraalCtrl` is `guigraal`'s residual name. The Torque field names above are not in that 6.00 image. |

## C++ GUI foundations (2026-11-12)

Stage 2 of the 3.x Torque rebuild: the pieces the canvas and the stock
controls draw with, as a standalone C++ library with no dependency on the
script VM or the sim objects. Nothing here is a console class yet; the
later `GuiCanvas`, `GuiControlProfile` and control objects wrap these.

| File | What it does |
|---|---|
| `image.hpp/.cpp` | RGBA8 image, bounded PNG reader (every PNG colour type and depth, no interlace, CRCs checked, system zlib) and an RGBA PNG writer for captures |
| `gft.hpp/.cpp` | `.gft` font cache reader, glyph lookup, text width, coverage |
| `bitmap_array.hpp/.cpp` | Splits a theme PNG into its pieces (bitmap array) |
| `canvas.hpp/.cpp` | Software canvas: clip stack, fill/frame, blit, stretch, tile, `.gft` text |
| `gui_inspect.cpp` | `gui-inspect` tool: `font`, `array`, `text`, `match` |

```
make -C common/torque/gui test     # hand-written fixtures, no original files
make -C common/torque/gui lab      # owner-supplied 3.04 files, see below
```

The `torque-gui` workflow builds and tests this folder on Linux (also under
address and undefined-behaviour sanitizers) and Windows.

### What each part was written from

- **`.gft` layout.** Graal_analysis `torque/study-torque-clients.md` §4
  gives the header (U32 1, height, baseline, glyph count). The rest was
  read from the 14 caches in the 3.04 install in the lab: 224 nine-byte
  glyph records (sheet, a byte that is 0 in every file, x, y, width,
  height, signed x origin, signed y origin, x advance), a sheet count, the
  sheets as 8-bit gray PNG streams back to back, and a 256-entry U16
  character map with 0xFFFF for characters 0 to 31. The full layout is in
  `gft.hpp`. The y origin is the number of rows from the top of the glyph
  to the baseline, so a glyph's top is `line top + baseline - y origin`.
- **Bitmap arrays.** The separator colour is the top-left pixel. Rows that
  are entirely that colour split the image into bands; inside a band,
  columns that are entirely that colour split it into cells. Read from the
  31 theme PNGs; see `bitmap_array.hpp`. Which profiles use a bitmap as an
  array, and what each cell index means to each control, is the next stage.
- **Canvas.** Straight-alpha source-over blending, nearest-neighbour
  stretch and text drawn by scaling the colour's alpha by glyph coverage
  are rebuild choices. 3.04 draws through OpenGL; the lab check below shows
  where the result already matches it exactly.

No TGE source, recovered code or original file is used or included. The
tests build their PNG and `.gft` inputs by hand, with stored (uncompressed)
deflate blocks, so no encoder under test makes its own input.

### Lab results (Linux 3.04 install, stage 0 main-menu screenshot)

`tests/lab_check.sh` takes `TORQUE304_RELEASE` (the install's `release/`
folder) and `TORQUE304_SHOT` (the 1024 × 768 stage 0 screenshot) and skips
when they are unset. Run on 2026-11-12:

- All 14 `.gft` caches load: 224 glyphs each, all 224 mapped, one sheet
  each except Arial 36 (two). Heights and baselines are listed in the script.
- The PNG reader decodes all 31 theme PNGs, both tile sheets and the
  screenshot to the same pixels as an independent decoder.
- Theme cell counts: button 36 (12 bands of 3: four states of a 3 × 3
  frame), check and radio 4, text edit 8 (the centre is separator-coloured,
  so the frame has no middle piece), gui border 9, slider 5, menu 18,
  border 8, window 24 (default) / 23 (mac, windows), scroll 52 / 39 / 51,
  cursors and the 3D arrow 1.
- Text: the button labels "Tutorial", "Options", "Get an account" and
  "Start", drawn in Arial 14 by `Canvas::draw_text` in the label colour over
  the button fill, match the screenshot **pixel for pixel** (every pixel
  within one level per channel), anti-aliased edges included. "Account:"
  and "Password:" (Arial 14) and "Welcome to Graal!" (Arial 20) sit on
  textured art; their glyph masks agree on 98.7 %, 98.3 % and 92.9 % of
  the box.

## Stock controls (2026-11-12)

The next stage on top of the foundations: the controls the 3.04 scripts
create, drawn from the console engine's object tree (`console/engine`) with
the profiles the scripts and the theme leave behind. `profile.hpp/.cpp` has
no engine dependency; `render.hpp/.cpp` and the `tq-shot` lab tool link the
engine and the compiler.

| File | What it does |
|---|---|
| `profile.hpp/.cpp` | `GuiControlProfile` fields as typed values (colours, flags, font, bitmap, justify, text offset) |
| `render.hpp/.cpp` | `Renderer`: layout, profile lookup, font and bitmap caches, drawing per control class |
| `host/tq_shot.cpp` | `tq-shot`: boots an install from its own `main.cs`, draws the canvas content (and `--dialog` controls) to a PNG |

```
make -C common/torque/gui test    # gui-test and render-test, hand-built fixtures
make -C common/torque/gui lab     # adds the menu render check below
```

### Where profiles come from

`defaultProfiles.cs` and `customProfiles.cs` create the profiles (`: Parent`
copies the parent's fields, which the engine already does), and the theme
script `common/ui/themes/<theme>/<theme>theme.th`, exec'd by `loadTheme()` in
`optionsDlg.cs` during the boot, assigns fields on them. The renderer reads
each field from the control's profile, then `GuiDefaultProfile`, then a
built-in default (rebuild policy). A control with no profile uses
`GuiDefaultProfile`.

A profile's `bitmap` is resolved relative to the script that created the
profile. Evidence: the theme sets `GuiTextEditProfile.bitmap =
"./themes/default/defaultTextEdit"`, which only names a real file relative to
`common/ui/defaultProfiles.cs`, and the stage 0 open order loads
`common/ui/themes/default/defaultTextEdit.png` when the menu wakes after the
theme ran; the screenshot shows its frame. When that path names no file the
renderer tries it relative to the theme script (rebuild policy, so that the
theme's `"./defaultWindow"` style values still find their image; no 3.04
capture of a window exists yet to settle it). Control bitmaps (`bitmap` on
`GuiChunkedBitmapCtrl` and `GuiBitmapCtrl`) are relative to the `.gui` that
created the control. Images are read up to `IEND`: the install's
`graalDarkButton.png` has one byte after it.

### Layout

Nothing is written back to the objects: every draw computes each rectangle
from the `.gui` `position` and `extent`, the parent's `.gui` extent and its
drawn size (rebuild policy). The content control fills the canvas. Sizing
follows the field names: `right`/`bottom` keep, `width`/`height` grow by the
parent's change, `left`/`top` move by it, `center` centres
(`(parent - size) / 2`, which puts `GraalLogin` at 111, 92 on an 800 × 600
canvas, as in the screenshot), `relative` scales. `minExtent` is a lower
bound. `GuiTextCtrl` with `autoSizeWidth` takes its text's width, and with
`autoSizeHeight` the font height plus 4, which reproduces the saved label
extents; this matters because the labels' text comes from the language file
(`"Language:"` is wider than its `.gui` extent of 44).

### Drawing

| Class | How |
|---|---|
| `GuiControl` | `opaque` fills with `fillColor`; `border` draws a one-pixel `borderColor` frame |
| `GuiTextCtrl` | One line in `fontColor`, justified in the box |
| `GuiButtonCtrl` | With a 36-cell array: nine cells per state (normal, highlighted, depressed, inactive), corners as they are, edges and centre stretched; label justified. `active = 0` draws the inactive set in `fontColorNA`. Without an array: fill and frame |
| `GuiTextEditCtrl` | The box filled with `fillColor`, then the eight-cell frame on top (the corner pieces are partly transparent and show the fill in the screenshot); text after the left piece plus `textOffset.x`, `*` for `password` |
| `GuiWindowCtrl` | Cell meanings read from the window images: title buttons (close, restore, maximize, minimize × normal, pressed, inactive), title bar ends and middle for active and inactive, left and right edges, bottom corners and bottom edge, and in the default theme a 64 × 64 background tile used when `tile` is set. Title in `fontColor` at `textOffset`; buttons for `canClose`, `canMaximize`, `canMinimize` right to left. The placement is rebuild policy until a 3.04 window is captured |
| `GuiChunkedBitmapCtrl`, `GuiBitmapCtrl` | The control's bitmap tiled (`tile` / `wrap`) or stretched to the box |
| `GuiTextListCtrl` | One row per line, font height + 2 tall; tab-separated columns at the `columns` offsets; the selected row filled with `fillColorHL` and drawn in `fontColorSEL`. The control grows to hold its rows |
| `GuiMLTextCtrl` | Plain text, word wrapped; no markup tags yet |
| `GuiConsole` | The newest lines of `Engine::console_buffer`, bottom-aligned |

The text list, multi-line text and console rules are rebuild policy, not
read from a 3.04 capture. A host can draw a class itself through
`Renderer::draw_hooks` (keyed by the lower-case class name); the 3.04 host
draws `GuiGraalCtrl` that way. `Renderer::hit(x, y)` finds the topmost visible
control drawn at a point, and `mouse_click` (`mouse.cpp`) turns a click into
the control's script call.

A text line's top is `(box height - (font height - 2)) / 2` inside its box.
That fits all seven stage 0 measurements (labels 18 and 23 rows tall start 3
rows down, the 25-row buttons 6).

Theme pieces are stretched bilinearly, with the source span inset by one
texel at each end along a stretched axis (`Canvas::smooth_stretch_blit`).
Plain nearest-neighbour stretching left 22 pixels per button wrong; the inset
bilinear rule reproduces the screenshot's left edge ramp (95, 89, 83, 76, 70,
64) and every button pixel exactly.

Bitmap arrays now trim each cell to its own rows: separator-coloured rows at
the top or bottom of a cell, within its columns, are cut. The window frame's
bottom pieces are 3 rows tall in a 9-row band. Cell counts are unchanged.

### Lab results (main menu, 2026-11-12)

`tq-shot` boots the Linux 3.04 install from its own `main.cs` and draws
`mainMenuGui` at 800 × 600, the size of the game area in the stage 0
screenshot. With `graalscreen.jpg` converted to PNG for the check (no JPEG
reader yet), `tests/lab_check.sh` gives:

- the four buttons (`Tutorial`, `Options`, `Get an account`, `Start`),
  `NickEdit`, `PassEdit` and the tiled background: **every pixel** within
  one level per channel;
- the labels on the textured art (`Nickname:`, `Language:`, `Account:`,
  `Password:`, `Welcome to Graal!`): exact as well;
- the whole 800 × 600 screen: 99.31 %. The rest is `LanguageBox` (pop-up
  menu, not drawn yet) and the text cursor in the focused `AccountEdit`.

### Not yet

- [x] `.gft` reader, theme bitmap-array splitting, software canvas surface.
- [x] `GuiControlProfile` fields from the `.th` scripts and `customProfiles.cs`, and which cell of each array a control draws per state.
- [x] Stock control rendering for buttons, text edits, windows, text labels and bitmaps, checked against the same screenshot.
- [ ] Pop-up menu, check box, radio, scroll and slider (text list, multi-line text and console are drawn, without captures to check them). The closed pop-up in the screenshot uses `defaultScroll.png`'s 3 × 3 frame (cells 42 to 50) and a down-arrow cell (39) at the right.
- [ ] Highlighted and depressed states, the text cursor and selection: they need input and the first responder.
- [ ] JPEG bitmaps (`graalscreen.jpg`), so the menu art draws without a converted copy.
- [ ] A 3.04 capture of a window (the options dialog) to settle the window layout and the theme-relative bitmap fallback.
- [ ] The mouse cursor. The surface is presented in a window by `../guigraal` (`graal304-torque`).
- [ ] Unicode or characters above 255: the 3.04 caches cover 32 to 255 only.
