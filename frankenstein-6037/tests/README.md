# Tests

`../test.sh` checks the scaffold manifest (v6.037, v5.120 from the 5.12 repro `graal-5.12-G3D14097`, UDP enabled,
placeholders `<server>`, `<port>`, `<md5>`).

A later test starts its own server and points the client at `<server>` and
`<port>`. Nothing here opens a public host.
