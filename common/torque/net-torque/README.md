# net-torque

**Patched.** The class is stock TGE `GameConnection` / `NetConnection`. 3.04 leaves it as the Torque demo. Later builds keep the class and change the handshake.

What it has to do later:

- 3.04: the demo connection. Game string `Torque Game Engine Demo`, protocol 9, no class-name table on the accept. Graal's TCP session is not this class.
- From 3.153, and on the 3D DLL in 4.x and 5.0: Graal's protocol on `GameConnection`. The accept path and the mission phases differ from the demo. This README does not specify bytes.
- 5.0.0.7 3D: one check lets only protocol 24 through.
- `TGraalConnection` is a Graal game type. It has no console methods. It stays outside this unit. In 3.04 it is not a child of `NetConnection`.

`torque/network.md` records the protocol 3.04, 3.153, 4.04r2, the 2006-09-19 Mac build and 5.12 accept (9, 19, 19, 21, 24). That Mac build was recorded as 4.20r6 but is the 4.11 Mac (`graal-4.11mac-G3D27076`), so 21 is a 4.11 Mac reading; no 4.20 build has a recorded number yet. A later implementation has to match those. The 4.2.0.8 Windows 3D note gives no protocol number, so none is stated for that DLL.

| Version | Linked? |
|---|---|
| 3.04 | Yes. Stock demo. |
| 3.153 | Yes. Patched: Graal protocol, still the monolith. |
| 4.04r2 3D | Yes. `GameConnection` is in that DLL. |
| 4.2.0.8 launcher | No. |
| 4.2.0.8 engine | No. The Graal session is the engine's own client, not `GameConnection`. |
| 4.2.0.8 3D | Yes. `GameConnection` is named. Mission phases fire `onGraal3DLoginStep` and send the two mission acks the note names. |
| 5.0.0.7 launcher | No. |
| 5.0.0.7 engine | No. `GameConnection` is absent. |
| 5.0.0.7 3D | Yes. `NetConnection` and `GameConnection`. Protocol window accepts only 24. |
| 5.30 / 5.31 | No. |
| 6.x | No. Unpacked 6.00 has no `GameConnection` and no `NetConnection`. The game socket is `quattro_lib`, not this unit. |
