# Graal 5.31r4 (scaffold)

The late-5 client, as far as the 5.30r3 and 5.31r4 images agree. Both are
one executable. FileVersion is `5.303` and `5.314`. The company string is
Linux Cyberjoueurs. The engine name in the image is `quattro_lib`. Torque
class names are absent. This folder does not build a player and does not
speak to a server.

No eight-character token is stored in either image, so the folder name
stays `graal-5.31r4`. The login line sends `G3D26090`, the documented
token for 5.30r3 and 5.31r4. The earlier 5.0.0.7 split (a host plus a
2D engine and a 3D plugin) is a different program. This folder does not
load those DLLs.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to Graal Online, Cyberjoueurs,
> or Stéphane Portha ("unixmad").

## What was read

Unpacked 5.30r3 and 5.31r4. The two file versions share the cut below.
Where a layout was not recovered, the unit leaves it unwritten.

| Fact | What the images show |
|---|---|
| Shape | One executable. No engine DLL beside it |
| Engine | `quattro_lib`. No Torque class names |
| Token | No stored eight-character literal. The login line sends `G3D26090` |
| Login | A host is baked beside port 14900. The host name is not copied here |
| Outbound | Opcode plus 32, the body, a newline. A newline in the body is rejected |
| Internal opcodes | Two opcodes skip that check. Their length-wrap bytes were not recovered, so they are not written |
| Flush | The outbound buffer goes out once it is longer than 4095 bytes, including the line that crossed |
| Inbound | A 2-byte big-endian length. 65535 is the long form: four more bytes, a big-endian length |
| Failure | A length below 1 is "illegal data (1)" and the reader is killed. The trigger for "illegal data (2)" was not recovered |
| Absent | An `onSend` table, a connector script, `Arc4Process`, an AES selector, and the "invalid data (3)" line |

## Units

| Unit | What it does |
|---|---|
| `src/Late531.pas` | the cut, the login line, the outbound line, and the inbound length header |
| `src/Graal531.dpr` | the shell: no arguments exits 0; `--show` prints the cut and the token |
| `tests/TestLate531.dpr` | the cut, the login token, the newline rule, the flush order, and the length header |

## Not yet

- [x] ~~A login token, once one is recovered. Do not invent an eight-character literal~~ The login line sends `G3D26090` for 5.30r3 and 5.31r4. The images store no literal.
- [ ] Numeric client-to-server opcodes. None were recovered as a fixed list
- [ ] The length-wrap bytes for the two internal opcodes
- [ ] The byte pattern that produces "illegal data (2)"
- [ ] Cipher or compression bytes inside a frame
- [ ] The local server-to-client switch, and any property id
- [ ] A window, a player, or a server connection
