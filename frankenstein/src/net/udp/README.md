# UDP

Placeholder. UDP support stays enabled in this client, including on the
game connection.

Stock v6.113 leaves the datagram socket off that path
(`docs/v6-repro.md`, UDP). The later code in this directory turns the path
on and keeps it on.

Bind and peer addresses are `<server>` and `<port>`. Any checksum written
down before a real check exists is `<md5>`.
