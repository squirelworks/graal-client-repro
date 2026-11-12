# What 4.04r2's start screen is drawn from, compiled in

4.04r2 (`Graal4.exe`, FileVersion 4.0.4.2) has no start window of its
own: its Torque engine draws the start screen inside the game window from
the install's GUI pictures in `levels3d/gui/`. These are those files,
renamed in capitals, compiled into the rebuild by
`scripts/res/make_resunit.py` (`src/Res404.pas`). The rebuild never
needs the original install to draw its start screen.

| File | From the 4.04r2 install | Used for |
|---|---|---|
| `GRAALV4SCREEN.jpg` | `levels3d/gui/graalv4screen.jpg` (555 x 463) | the house, centred in the window |
| `GRAALV4TITLE.png` | `levels3d/gui/graalv4title.png` (385 x 172) | the title art over it |
| `DEFAULTTEXTEDIT.png` | `levels3d/gui/defaulttextedit.png` | the edit boxes' gold edge (nine 5 x 5 pieces) |
| `DEFAULTSCROLL.png` | `levels3d/gui/defaultscroll.png` | the combo box's red shield arrow |
| `DEFAULTRADIO.png` | `levels3d/gui/defaultradio.png` | the Member radio button |
| `DEFAULTCHECK.png` | `levels3d/gui/defaultcheck.png` | the Save password box |
| `../src/Graal404.ico` | GROUP_ICON MAINICON of `Graal4.exe` (32 x 32) | the window and taskbar icon (through `src/Graal404.rc`) |

Byte for byte the install's files. The icon is the same picture as 2.22's.

Not taken, and why:
- the forms in `Graal4.exe` (TGRAALWINDOW, TOPTIONS, TPLAYERLIST and the
  rest): the game window's size is written into the rebuild instead; the
  others belong to windows not built yet;
- VERSIONINFO: the rebuild keeps its own (graal-delphi, squirelworks) so it
  is never taken for the original program;
- the VCL's own bitmaps, cursors and strings: Delphi library parts, not
  Graal's.
