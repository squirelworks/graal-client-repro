# v5.120 Graal3D

v5.120 is the 5.12 client, written the way the 6.x builds are
(6.03r7 is v6.037, 6.1.1.3 is v6.113). Its rebuilds are
[`graal-5.12-G3D14097`](../../../graal-5.12-G3D14097/) (Windows, token
`G3D14097`) and
[`graal-5.12mac-G3D15097`](../../../graal-5.12mac-G3D15097/) (Mac OS X,
token `G3D15097`, built from the same engine source). Their 3D library is
`common/cpp/graal3dengine`, which this client links directly.

`view3d.hpp` / `view3d.cpp` is the stand-in view: the 5.12 repro reads the
world but draws none of it yet. It fills the frame with the sky's fog
colour and the ground, draws a ground grid and each `GameObject` as a box,
seen from 8 units behind and 4 above the player's object, and puts the 6.x
frame in a quarter-size inset. None of it is the original's look. The real
renderer belongs in `common/cpp/graal3dengine`, for every 3D build.

No modern Torque3D base. A small MIT-licensed piece from modern Torque3D
is allowed only where that older Torque needs it.
