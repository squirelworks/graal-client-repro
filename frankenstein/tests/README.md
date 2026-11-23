# Tests

`../test.sh` checks the scaffold manifest (v6.113, v5.120, UDP enabled,
placeholders `<server>`, `<port>`, `<md5>`).

A later test starts its own server and points the client at `<server>` and
`<port>`. Nothing here opens a public host.
