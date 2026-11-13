# stb_image and stb_truetype

`stb_image.h` v2.31 from https://github.com/nothings/stb, unchanged. Public
domain or MIT, at the user's choice (the licence is at the end of the
file). Not Graal code.

`common/cpp/graalengine` uses it for the JPEG, GIF and BMP pictures the
4.x menus name (`graalv4screen.jpg` and the like); PNGs go through the
Torque GUI layer's own reader (`common/torque/gui/image.cpp`).

`stb_truetype.h` v1.28 from the same repository, unchanged, same licence.
`common/torque/gui/system_font.cpp` uses it to build Torque fonts from a
TrueType file when an install ships no `.gft` cache (3.153), and
`common/torque/gui/jpeg.cpp` uses `stb_image` for the Torque menus' JPEG
art. Both compile the implementation `static`, so each library keeps its
own copy without symbol clashes.
