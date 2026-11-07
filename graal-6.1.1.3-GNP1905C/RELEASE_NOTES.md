# Graal 6.1.1.3 (`GNP1905C`)

The first rebuild of the unpacked Windows 6.1.1.3 client. The original is a
`quattro_lib` program. This folder is original Pascal. It is not a Torque
host and it does not borrow another version's token.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

## What's new in v0.0.5

- A window (when `--window` can open one), a software camera, a local
  player, and lab-only collision on `levels/lab-yard.lvl`.
- TCP to `127.0.0.1`. The documented clear hello is `GNP1905C` with no
  header. The session stops there unless `--lab` is set.
- `--lab` is a labeled lab-only fixture: one other entity, its properties,
  and a movement round trip. It is not 6.1.1.3 ciphertext and not v7.

## Not yet

- [ ] The cipher after the clear hello. `setencryptionout` names `AES` and
  `RC4`, and the notes disagree on the generation-5 step (`+ 1` versus
  `+ key`). Neither mix is applied on the socket.
- [ ] The `setprotocol` template. The capture header is a size check, not
  a recovered template, so the connect path does not call `setprotocol`.
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
