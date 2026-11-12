# What 2.3 is built from, compiled in

No 2.3 program survives: graal_analysis's version profile for 2.3 says "no
binary: everything as 2.31". So 2.3 is modelled on **2.31**, its nearest
real neighbour (GNW14015, then GNW28015 a few weeks later). Every file here
is the same file as in `graal-2.31-GNW28015/res/`, taken out of the real
2.31 client's resources (`Graal_231.exe`, FileVersion 2.3.1.0), and is
compiled into the rebuild by `scripts/res/make_resunit.py`
(`src/Res230.pas`). The rebuild never needs an original program to run.

| File | Resource in Graal_231.exe | Used for |
|---|---|---|
| `SCREENIMG1.jpg` | RCDATA SCREENIMG1 (577 x 416) | the start window's background |
| `SCREENIMG2.jpg` | RCDATA SCREENIMG2 (577 x 416) | the server list's background |
| `BUTTON1.bmp` .. `BUTTON4.bmp` | RCDATA BUTTON1 .. BUTTON4 | the picture buttons and the Go button |
| `TUTORIALA1.graal` .. `TUTORIALC3.graal` | RCDATA TUTORIALA1 .. TUTORIALC3 | Training: offlinetutorial_a-1 .. c-3 |
| `OPENGLYPH.bmp` | the TOPENURL form's Open button glyph (15 x 14) | the "Open URL" box's Open button |
| `TOPTIONS.dfm` | RCDATA TOPTIONS (the form, as it is) | the F1 "Help" window (common/GOptionsWindow) |
| `../src/Graal230.ico` | GROUP_ICON MAINICON | the window and taskbar icon |

The pictures and the levels are also byte for byte 2.22's, so they were in
2.3 too, whichever of the two 2.3 looked like. The icon is 2.31's.
