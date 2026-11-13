# graal3dengine: the 4.x/5.0 3D library

The 4.04r2 to 5.12 Windows clients load a third program on demand, the
first time the player picks a server whose list name starts with `3 `:
`Graal3DEngine.dll`, a cut-down Torque world. This folder is that library
for the rebuild (plan Track C4). It sits beside the engine library
([`../graalengine`](../graalengine)), links against it as the original
imports from `GraalEngine.dll`, and fills the engine's 3D slots.

```
make            # build/libgraal3dengine.so, or build/Graal3DEngineRepro.dll on Windows
make test       # the link against the recorded vectors, both libraries over loopback UDP, the export check
```

`scripts/build.sh` builds it with the engine library for the 4.04r2 and
5.12 folders and copies it next to the launcher.

## What it does now

The 3D session's UDP side, protocol 24 (5.00r7, 5.12) and 21 (4.20), from
the connect to login step 6:

| Piece | Does | From |
|---|---|---|
| `src/bits.*` | The Torque bit stream: LSB-first fields, `string` (Huffman or raw) and `pstring` (the per-packet prefix buffer) | `torque/udp-session.md` §2 |
| `src/link.*` handshake | Challenge (`0x1A`), connect request (`GameConnection`, group 0, CRC `0xFFFFFFFF`, `Graal3D`, the protocol twice, the password, account and nickname), Graal's class table in the accept, the protocol check; resent every 500 ms, given up after 15 s with the real client's sentence | §3 |
| `src/link.*` packets | The data-link header, 9-bit sequences widened, ack masks, delivered/lost notification, at most 30 packets in flight, a ping answered with an ack, every server data packet answered at once, a keep-alive each second, the 30 s silence time-out | §4 |
| `src/link.*` events | Unguaranteed and guaranteed-ordered lists with Graal's 14-bit length prefix, held back until in order, lost ones sent again; `NetStringEvent` tags, `RemoteCommandEvent`, `BigDataStartEvent`/`ChunkEvent` both ways (none, zlib, bzip2 in; none out) | §5, §7 |
| `src/link.*` mission start | `MissionStartPhase1` → step 2 and `MissionStartPhase1Ack`; `MissionStartPhase2` → steps 3, 4 and `MissionStartPhase2Ack`; the first control object after phase 2 → steps 5 and 6 | §7, `torque/4208-g3d.md`, `torque/5007-g3d.md` |
| `src/world.*` | Ghost creates, updates and deletes; `GameObject` (all thirteen sections), `Camera`, `Sun`, `Sky` (name, material list, fog colour); any other class skipped by its length | §8 |
| client game section | First person, the control object's position and ghost, its shape, transform and flags sent back once, then an empty update | §6 |
| `src/exports.cpp` | `loadGraal3DEngine` registers `ConnectTo3DServer`, `RemoveGraal3DConnection`, `SendGraal3DScriptEvent(s)`, `RemoveGraal3DMissionGroup` on the engine, clears the launcher's `StartGraal3D` and initialises the engine again; `runGraal3DEngine` is one frame of the link on a UDP socket; `endGraal3DEngine` sends the disconnect | `graal3d/torque-engine-4x.md`, `torque/5007-g3d.md` |

The engine library's half (`../graalengine`): a `3 ` server with these
slots filled sets 3D mode, calls `ConnectTo3DServer(host, port + 1)` and
then logs in on TCP exactly as for a 2D server; `getGraalLoginInfo` gives
the account, nickname and password (the built-in guest on 5.x);
each login step raises `onGraal3DLoginStep(step)` on the universe and step
6 makes `GUIContainer3D` (4.x) or `GUIContainer` (5.x) the content;
`setGraal3DConnectionError` drops the TCP session too.

### Checked against

- The real 5.12 client's connect request: the writer gives the same 71
  bytes. Its first two data packets: the same 19 and 17 bytes.
- The empty and the full protocol-24 connect accepts (19 classes).
- The Seihai gserver's `GameObject`, `Sun` and `Sky` payloads (bit counts
  471 and 379 exactly; the `GameObject` written back is the same bits).
- The whole recorded server session (§8): the link's own packet numbering
  meets each server packet's acks, the acks go out in order, and it ends at
  step 6 with the player's object as the control object.
- Both libraries as shared libraries over loopback UDP: `make test` runs a
  UDP server that answers the handshake and replays that session, and the
  engine reports login step 6.

No real client has run against this library yet: it is not loaded by a
launcher (below), and a lab run against the Seihai gserver's
`graal3d = true` mode is the next check.

## What it was written from

Graal_analysis, behaviour only: `torque/udp-session.md` (the client's
order, with the vectors), `torque/lab-2026-11-12-udp-trace.md`,
`graal3d/torque-engine-4x.md`, `torque/4208-g3d.md`, `torque/5007-g3d.md`,
`torque/g3d-5007.md`. Nothing from a decompile and no TGE 1.x source.

The string Huffman table and its tree are Torque3D's (MIT), in
[`../third_party/torque3d`](../third_party/torque3d) with their notice;
every Graal build uses the same table. The rest is this rebuild's own.

## What is the rebuild's own

- The argument lists of the exports and the engine's 3D bridge
  (`isGraal3DMode`, `getGraalLoginInfo`, `setGraal3DConnectionError`), as
  in `graalengine.h`. `SendGraal3DScriptEvent` takes one event line.
- The `graal3dengine_*` exports (status and the connect sequence, for
  tests) and the engine's `graalengine_build`,
  `graalengine_graal3DLoginStep` and `graalengine_logLine`. In the
  original the 3D library raises the event and sets the canvas content on
  the engine's objects itself.
- Resend and keep-alive timing (500 ms, 1 s); the connect sequence is
  taken from the clock.

## Not yet

- [x] ~~The launcher (`common/GEngineHost.pas`) loading this library on
  `StartGraal3D`, connecting again and calling `runGraal3DEngine` each
  frame~~ (the 5.12 launcher test checks it)
- [ ] A lab run with the rebuilt 5.12 against the Seihai gserver's 3D mode
- [ ] Drawing: the Torque world (terrain, interiors, DTS and `.3ds`
  shapes, sky, sun) in `GraalControl3D`, and the draw slots the original
  takes over
- [ ] Step 6 waits for the engine's TCP file downloads; the shapes and sky
  textures fetched over TCP
- [ ] The TCP session in 3D mode ignoring level boards, warps and flags
- [ ] Server text: weapons, `addnpc`, flags and `events` handed to the GS2
  machine (logged only now); the client's events zipped over 49 bytes
- [ ] Protocol 19 (4.04r2) past the handshake: datablocks, moves, the
  stock ghost classes (never run on a real client either)
- [ ] Movement (`movetype` and its data) and the player's own moves sent
  back; `TerrainChunkEvent` and the `levels3d/heights` cache
- [ ] The `fixedudpport` option (14899) for the client's UDP port
