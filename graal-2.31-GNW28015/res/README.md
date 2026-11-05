# What 2.31's own program carries, compiled in

These files were taken out of the real 2.31 client's resources
(`Graal_231.exe`, the "Graal Reborn 2.22.0" install, FileVersion 2.3.1.0)
and are compiled into the rebuild by `scripts/res/make_resunit.py`
(`src/Res231.pas`). The rebuild never needs the original program to run.

| File | Resource in Graal_231.exe | Used for |
|---|---|---|
| `SCREENIMG1.jpg` | RCDATA SCREENIMG1 (577 x 416) | the start window's background |
| `SCREENIMG2.jpg` | RCDATA SCREENIMG2 (577 x 416) | the server list's background |
| `BUTTON1.bmp` .. `BUTTON4.bmp` | RCDATA BUTTON1 .. BUTTON4 | the picture buttons (up and pressed halves) and the Go button |
| `TUTORIALA1.graal` .. `TUTORIALC3.graal` | RCDATA TUTORIALA1 .. TUTORIALC3 | Training: offlinetutorial_a-1 .. c-3 |
| `../src/Graal231.ico` | GROUP_ICON MAINICON (32 x 32) | the window and taskbar icon (through `src/Graal231.rc`) |

Byte for byte the same as 2.22's: the pictures and the tutorial levels.
2.31's own: the icon (a few pixels differ from 2.22's).

Not taken, and why:
- the forms (TCONNECTFRAME, TSERVERLISTFRAME, TADVENTURE and 15 more): their
  places and sizes are written into `src/RealStart231.pas` and
  `src/Adventure.pas` instead, with the form named at each place;
- VERSIONINFO: the rebuild keeps its own (graal-delphi, squirelworks) so it
  is never taken for the original program. The original's says
  CompanyName "Linux Cyberjoueur", FileDescription "RPG online game
  application file", FileVersion 2.3.1.0;
- the VCL's own bitmaps, cursors and strings (BBOK, CL_MP*, the
  RT_STRING tables): Delphi library parts, not Graal's.
