# Graal 6.1.1.3 (`GNP1905C`)

The first rebuild of the unpacked Windows 6.1.1.3 client. The original is a
`quattro_lib` program. This folder is original Pascal. It is not a Torque
host and it does not borrow another version's token.

**Login token: tested against the real client.** The original was run in the lab and `GNP1905C` was seen in its login on the wire (lab capture of its hello); this rebuild sends the same token.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

## What's new in v0.0.4.2

- A window (when `--window` can open one), a software camera, a local
  player, and lab-only collision on `levels/lab-yard.lvl`.
- TCP to `127.0.0.1`. The documented clear hello is `GNP1905C` with no
  header. The session stops there unless `--lab` is set.
- The client registers the 6.1.1.3 control names and opens `GraalControl`
  as a stub. The window is unchanged. The hello stays `GNP1905C`.
- Connector login (`--connector 127.0.0.1:PORT`): GET `conf.gs`, check
  its RSA-2048 signature over the bare SHA-256 digest with the project's
  own public key before anything runs, then run the connector script:
  `setProtocol("EILLLT")`, `sendRaw`, `setEncryptionOut`. The project
  script's token is the placeholder `SEI00001`. **Not yet usable**: the
  client stops after the hello until seihai-gserver-v2 handles `SEI00001`.
  `--connector-serve` serves a signed `conf.gs` on loopback for testing.
- The generation-5 seed is the one `protocol/unpacked-6113-wire.md` gives.
  It was 128 too high before.
- `--lab` is a labeled lab-only fixture: one other entity, its properties,
  and a movement round trip. It is not 6.1.1.3 ciphertext and not v7.

## Not yet

- `scripts/loopback.sh` expects the clear `GNP1905C` hello and the
  documented stop. It does not invent the cipher or count a gserver
  login. `scripts/stress.sh` does not soak this folder.
- [ ] The cipher after the clear hello. `setencryptionout` names `AES` and
  `RC4`, and the notes disagree on the generation-5 step (`+ 1` versus
  `+ key`). Neither mix is applied on the socket.
- [ ] The `setprotocol` template on the clear-hello path. The connector
  path uses `EILLLT`, from the connector script.
- [ ] `SEI00001` on the game server (seihai-gserver-v2), the project's
  `conf.gs` payload cipher, and the session cipher.
- [ ] Property value widths. The four setters store the string. The id
  prefix is id plus 32. The bytes after that prefix were not recovered.
- [ ] GS2 opcode bodies, the builtin table, and where the `GRESCR01` CRC
  is stored.
- [ ] OpenGL, `GuiGraalCtrl`, and the original window size. This window is
  the repo's software surface at a lab view size.
- [ ] A datagram socket. The connect path does not open one. The script
  bind that logs "Binding of port" is not implemented.
- [ ] macOS was not run here.

## Downloads

No zip from this folder yet. Releases are the combined graal-delphi release.
