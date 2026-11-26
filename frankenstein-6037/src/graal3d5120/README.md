# v5.120 Graal3D

v5.120 is the 5.12 client, written the way the 6.x builds are
(6.03r7 is v6.037, 6.1.1.3 is v6.113). Its rebuilds are
[`graal-5.12-G3D14097`](../../../graal-5.12-G3D14097/) (Windows, token
`G3D14097`) and
[`graal-5.12mac-G3D15097`](../../../graal-5.12mac-G3D15097/) (Mac OS X,
token `G3D15097`, built from the same engine source). Their 3D library is
`common/cpp/graal3dengine`, which this client links directly.

`view3d.hpp` / `view3d.cpp` present the world with the 5.12 repro's
renderer (`common/cpp/graal3dengine/render`), the same one every 3D build
uses: the sky, the shapes in `levels3d/`, the streamed terrain, water,
replicator cover and name tags. Until the server names a Camera the view
is black, as the 5.12's is. The player's draw distance comes from a
5.12-style `game_config.txt` (`visibledistance3D`, beside the program or
in an asset root; 1000 when none sets it, at most 2400). The 6.x frame
stays in a quarter-size inset.

No modern Torque3D base. A small MIT-licensed piece from modern Torque3D
is allowed only where that older Torque needs it.
