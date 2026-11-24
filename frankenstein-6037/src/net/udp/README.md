# UDP

`link3d.hpp` / `link3d.cpp`: `Frank::Link3D`, the 5.12 repro's Graal3D link
(`graal3d::Link`, protocol 24) on a `graal3d::UdpSocket`. It is the glue
the 5.12 library's `exports.cpp` is for the engine library: datagrams in,
the link's clock, datagrams out, and a failed or closed link dropped
before the host hears of it.

Stock notes (`docs/v6-repro.md`, UDP) say a 6.x connect path does not open
a datagram socket. This client opens one for every `3 ` server, on a random
local port (the 14899 `fixedudpport` option is not read), to the listed
port + 1.

Bind and peer addresses in docs are `<server>` and `<port>`. Any checksum
written down before a real check exists is `<md5>`.
