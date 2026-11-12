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

### Not yet

- [x] `.gft` reader, theme bitmap-array splitting, software canvas surface.
- [ ] `GuiControlProfile` fields from the `.th` scripts and `customProfiles.cs`, and which cell of each array a control draws per state.
- [ ] Stock control rendering (button, text edit, window, scroll, check box, pop-up menu) on this canvas, checked against the same screenshot.
- [ ] `GuiCanvas` console object (`setContent`, `pushDialog`, cursor) once the sim layer exists, and presenting the surface through `host304`.
- [ ] Unicode or characters above 255: the 3.04 caches cover 32 to 255 only.
