# Graal 6.1.1.3 (`GNP1905C`)

Unpacked Windows 6.1.1.3, rebuilt far enough to run. The original is one
`quattro_lib` program: OpenGL, `TSocket`, GS2, no `SimObject`, no
`GameConnection`, no `horizSizing`. A parenthetical that calls the target
"the TGE 1.2 lineage" does not match that reading. This folder follows the
notes and does not link `common/torque`.

The token on the wire is `GNP1905C`. It is not stored in the image, and
this folder does not invent a second token or a formula for `1905`.

Three layers are marked in the units and below.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

## Gap against "TGE 1.2 lineage"

| TGE 1.2 idea | What the merged notes say | What this folder does |
|---|---|---|
| `SimObject`, console, `horizSizing` | Absent in unpacked 6.1.1.3, as in unpacked 6.00 | Not implemented |
| `GameConnection` and a Torque datagram on the connect path | The game connect path does not open a datagram socket | TCP only. `UdpOpens` stays 0 |
| Torque `Player` and a mission camera | No movement constant in this image. 6.00/6.03 lab timings are not copied | Lab-only step and camera |
| Stock GUI field layout | `GuiGraalCtrl` is still a type the GUI walk compares. `GuiGraal3DCtrl` is not a string. `GuiTilesCtrl` is registered | Not those classes. A software surface |

Sources: `client-internals/unpacked-6113.md`, `client-internals/engine-6113.md`
(the packed stub, which is not the engine), manual sections 10.1.9 and
10.1.12, manual section 2.9.5, `protocol/v6113-udp.md`.

## Layers

| Layer | What it is |
|---|---|
| verified-from-evidence | Clear hello, `sendraw`, the `setprotocol` fill rules, generation-5 newline refusal and the 4096 flush, the LCG seed and the `+ 1` step, the `setencryptionout` names, property stores, the id-plus-32 prefix, `onToall`'s length check, `GRESCR01`, the named GS2 cases, TCP with no datagram on connect |
| provisional adapter | The repo window and software surface instead of OpenGL. zlib through `GZlib`. bzip2 through `GBzip2` with the block-size digit set to 5. Not byte-identical to zlib 1.2.5 or libbzip2 |
| lab-only fixture | `levels/lab-yard.lvl` (`LABLVL1`), the colours, the 4-pixel step, collision, the camera clamp, and every byte after `GNP1905C` when `--lab` is set. Not 6.1.1.3 compatibility and not v7 |

## Evidence

| Claim | Note |
|---|---|
| `GNP1905C` is sent before any server byte, and it is not a stored string | `protocol/v6113-hello.md`, `protocol/v6113-list-capture.md`, manual section 2.10.5 |
| `sendraw` writes those eight bytes with no header | `protocol/v6113-hello.md`, `protocol/v6113-pli.md` |
| After `setprotocol`, the header is filled T, I, E, L. `L` is header plus body. `E` 1 is zlib at 48 bytes. `E` 2 is bzip2, block size 5, at 4096 bytes | `protocol/v6-repro-facts.md`, `protocol/v6113-hello.md` |
| Numbered send refused until both `L` and `T` exist | `protocol/v6-repro-facts.md` |
| Generation-5 LCG is the default until `setencryptionout`. Seed and `+ 1` | `protocol/unpacked-6113-wire.md` |
| The hello note instead adds the key. The session cipher was not found | `protocol/v6113-hello.md` |
| 6.037 sends upper-cased `g3d0311c` as id 5. 6.1.1.3 does not | manual section 2.3.7, `protocol/v6037-hello-diff.md` |
| Connect path does not open a datagram socket | manual section 2.9.5, `protocol/v6113-udp-code.md` |
| The four `tclient_set*` methods store one string. Player ids 0..83, twelve without a case | `protocol/v6-props.md` |
| `onToall` takes an id and a counted text | `protocol/v6-repro-facts.md` |
| `GRESCR01`, 152 dispatcher cases, 48/49/200 absent, 54/121/201..242 present | `client-internals/gs2-6113.md`, manual section 8.4.4 |
| Level magics `GR-V1.03` through `GR-V1.05` are names only here. `GLEVNW01` is absent | `protocol/unpacked-6113-wire.md` |

## Running it

From the repo root, after `scripts/build.sh graal-6.1.1.3-GNP1905C`:

```
build/graal-6.1.1.3-GNP1905C/Graal6113 \
  --level graal-6.1.1.3-GNP1905C/levels/lab-yard.lvl --window --frames 40 \
  --keys "right*8,down*4"

build/graal-6.1.1.3-GNP1905C/Graal6113 --lab-serve 14900 --seconds 20

build/graal-6.1.1.3-GNP1905C/Graal6113 \
  --server 127.0.0.1:14900 --lab \
  --level graal-6.1.1.3-GNP1905C/levels/lab-yard.lvl \
  --frames 20 --keys "right*6"
```

Without `--lab`, the client sends the eight clear bytes and stops. Further
server bytes are counted and not decoded. `--password-env` is accepted and
the value is never sent or written to the log. `--account` is not placed
on the wire: the login body after the token was not recovered.

`--server` must be `127.0.0.1` and a port. That is a limit of this rebuild,
not a claim about the original.

The lab server speaks only after `GNP1905C`. Its marker is the text
`LABONLY`. Do not point a real 6.1.1.3 client at it and call the result a
match.

## What the picture is

`--window` opens the repo's X11, GDI, or Cocoa window at 240 by 180. The
level is drawn in solid colours (floor, wall, local player, other entity).
The camera keeps the local box in view and stays inside the level. Arrow
keys or `--keys` move by 4 pixels when the destination does not overlap a
`#` cell. None of those numbers were recovered from the image.

Without `--window` the same frames are computed and can be written with
`--dump`. A dump is not the window.

## Wire

1. TCP connect. No datagram socket is opened.
2. `sendraw` of `GNP1905C`.
3. Stop, unless `--lab`.
4. `--lab` then uses length-prefixed lab messages: ready, your id, a spawn
   of one other entity, a property update, and a move echo.

`setprotocol` is implemented and tested. The connect path does not call it,
because the template string is not in the image. A test template of six
bytes with a 273-byte body writes `L` as 279. That is the size check from
the hello note. It is not the captured header `01 02 00 01 17 fd`.

`setencryptionout("AES")` and `setencryptionout("RC4")` record the name and
do not transform bytes. Any other name clears back to the LCG default.
Generation-5 numbered sends are refused. Ids 93 and 163 would need the
id-50 prefix; the byte order of that prefix was not recovered.

## GS2 surface this slice uses

`Gs26113` accepts a buffer of at least eight bytes starting with `GRESCR01`
and records that the CRC32 covers the following bytes. It does not check a
CRC, because the stored location was not recovered. It classifies opcode
numbers the note names. It does not execute any opcode.

## Unsupported

- [ ] Opcode bodies, and the case numbers the note does not name one by one.
- [ ] The builtin table. It was not extracted.
- [ ] Chat send. `onToall` can be parsed. No PLO id is assigned to it, so
  nothing is sent for it.
- [ ] File transfer, `basepackage.gupd` requests, `creationtime.dat`.
- [ ] The script connector (`StartScript_Connector` / `StartScript_Fail`)
  and the bytes that script would send.
- [ ] UDP bind. The image can open a datagram socket from script. This
  connect path does not, and the bind method is not implemented.
- [ ] AES, RC4, and the generation-5 XOR mix. The mix width (12 dwords, or
  4 on a compressed frame) is described; which bytes of the LCG word are
  applied was not pinned down against the two step formulas, so it is not
  applied.
- [ ] `GR-V1.03`, `GR-V1.04`, `GR-V1.05` bodies.
- [ ] Original window size, fonts, tiles, ganis, audio.

## Provenance

New code in this folder is original Pascal written for this rebuild. No
new dependency. It uses Free Pascal and the units already in this repo
(`GWindow`, `GSurface`, `GSocket`, `GZlib`, `GBzip2`), on the same terms as
the rest of graal-delphi. No C++ was added. No decompiled body was copied.

## Not yet

- [ ] Cipher, template, and property value widths. See the table above.
- [x] The 6.1.1.3 control names, including `GuiGraalCtrl` and `GuiTilesCtrl`, are registered when the client runs. The bodies are stubs. The window stays the software surface. The clear hello stays `GNP1905C`.
- [ ] OpenGL and the real playfield classes.
- [ ] GS2 execution.
- [ ] Side-by-side against the real 6.1.1.3 client.
- [ ] macOS was not run in this environment. A skipped macOS job is not a pass.
