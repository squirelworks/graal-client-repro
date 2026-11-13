# What the later Graal3D beta's own program carries, compiled in

Taken out of the real later-beta `Graal3D.exe` (630,272 bytes, SHA-256
`7c6bb8e8b1dd10620f9b12f108accd274bd436016a00433e256d2ec7bfd9562c`, from
"New Graal 3D Beta Version.rar" in the project's client archive) and
compiled into the rebuild by `scripts/res/make_resunit.py`
(`src/Res3D.pas`). The rebuild never needs the original program to run.

| File | Where in Graal3D.exe | Used for |
|---|---|---|
| `STARTIMAGE.jpg` | RCDATA TCONNECTFRAME, `Image1.Picture.Data` (a TJPEGImage, 433 x 321) | the start window |
| `../src/Graal3D.ico` | GROUP_ICON MAINICON (32 x 32, the torch) | the window and taskbar icon (through `src/Graal3D.rc`) |

Both were compared with the February 2000 program's: the start picture is
byte-identical (SHA-256 `886961685fdcb479…`, also shipped loose in the RAR
as `startscreen.jpg`), and the icon image is the same, so the files here
are this build's own and equal to `graal-3d-20000205`'s.

Not taken, and why:
- the forms (TADVENTURE, TCONNECTFRAME, TMOREOPTIONS, TEDITLOOK and the new
  TDRIVERSFORM): their sizes, captions and places are written into
  `src/Connect3D.pas` and `src/Graal3D.dpr`, with the form named at each
  place;
- there is no VERSIONINFO in Graal3D.exe; the rebuild keeps its own;
- the VCL's own bitmaps, cursors and strings (Delphi library parts).
