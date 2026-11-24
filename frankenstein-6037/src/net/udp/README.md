# UDP

Placeholder. UDP support stays enabled in this client, including on the
game connection.

Stock notes (`docs/v6-repro.md`, UDP) say a 6.x connect path does not open
a datagram socket. For 6.0.3.7, whether the game connect path calls the
opener is not found. The later code in this directory turns the path on
and keeps it on.

Bind and peer addresses are `<server>` and `<port>`. Any checksum written
down before a real check exists is `<md5>`.
