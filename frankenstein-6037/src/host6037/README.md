# v6.037 host

`host.hpp` / `host.cpp`: `Frank::Host`, the Frankenstein's host.

The 2D side is `common/cpp/quattro`'s `Shell::Program` on the 6.03r7 row,
as in [`graal-6.03r7win-G3D0311C`](../../../graal-6.03r7win-G3D0311C/)
(Windows, token `G3D0311C`) and
[`graal-6.03r7-G3D0511C`](../../../graal-6.03r7-G3D0511C/) (Linux, token
`G3D0511C`): the Windows build sends the Windows row, Linux and macOS send
the Linux row. [`docs/v6-repro.md`](../../../docs/v6-repro.md) has the notes.

What the host adds is the 5.12 engine library's `3 ` server
(`common/cpp/graalengine`, `Engine::connect`): the marker is stripped,
the Graal3D link opens on the listed port + 1, then the program logs in on
TCP as for any server. A Login-server 178 warp to a `3 ` name is taken
from the session and goes the same way. In 3D mode the scripts' server
triggers go over the link as `events` lines, server text from the link goes
to the program's GS2 machine, and a link failure ends both links.
