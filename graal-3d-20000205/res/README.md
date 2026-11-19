# What Graal3D's own program carries, compiled in

Taken out of the real `Graal3D.exe` (February 2000, 605,184 bytes, in the
`graal3d` folder of the project's client archive) and compiled into the
rebuild by `scripts/res/make_resunit.py` (`src/Res3D.pas`). The rebuild
never needs the original program to run.

| File | Where in Graal3D.exe | Used for |
|---|---|---|
| `STARTIMAGE.jpg` | RCDATA TCONNECTFRAME, `Image1.Picture.Data` (a TJPEGImage, 433 x 321) | the start window: the wood board, the "Graal 3d" title and the field names |
| `../src/Graal3D.ico` | GROUP_ICON MAINICON (32 x 32, the torch) | the window and taskbar icon (through `src/Graal3D.rc`) |

Not taken, and why:
- the forms (TADVENTURE, TCONNECTFRAME, TMOREOPTIONS, TEDITLOOK): their
  sizes, captions and places are written into `src/Connect3D.pas` and
  `src/Graal3D.dpr`, with the form named at each place;
- there is no VERSIONINFO in Graal3D.exe; the rebuild keeps its own;
- the VCL's own bitmaps, cursors and strings (Delphi library parts).

## Now graal-delphi's own art (2026-11-19)

Every picture, icon, cursor and level listed here has since been redrawn by
`scripts/art/make_art.py` in the same name, size, format and layout
([docs/art.md](../../docs/art.md)); the sizes and checksums above are the
original program's. Forms keep their layout and captions, with new
pictures inside. To use the original's own files, put them in `assets/`
beside the program ([docs/assets.md](../../docs/assets.md), "Your own files").
