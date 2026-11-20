# Graal 5.31r4 (scaffold)

The late-5 client, as far as the 5.30r3 and 5.31r4 images agree. Both are
one executable. FileVersion is `5.303` and `5.314`. The company string is
Linux Cyberjoueurs. The engine name in the image is `quattro_lib`. Torque
class names are absent. The Pascal program does not
speak to a server itself; it hands the game to the Quattro program.

No eight-character token is stored in either image. The login line sends
`G3D26090`, the documented token for 5.30r3 and 5.31r4, so the folder
carries it as every other tokened client does: `graal-5.31r4-G3D26090`. The earlier 5.0.0.7 split (a host plus a
2D engine and a 3D plugin) is a different program. This folder does not
load those DLLs.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to Graal Online, Cyberjoueurs,
> or Stéphane Portha ("unixmad").

## Repro tracks

Policy: [docs/engine-repro-policy.md](../docs/engine-repro-policy.md).

- **default:** the Quattro program. `Graal531 --server HOST:PORT --account NAME` or `Graal531 --level FILE` hands the game to the `quattro-play` beside it (row `5.31r4 Windows`, `G3D26090`). With no arguments it opens the start screen (5.24r4's list step and character, on `common/GStartScreen.pas`), and Training or the picked server plays in `quattro-play`.
- **faithful engine:** Quattro one-exe program (`quattro-play`): login, the 178 warp, level and walk in the program tests, and logged in to seihai-gserver on loopback, classic and Seihai secure login (`SEI00001`).
- **relic / fallback:** the Pascal scaffold (`Late531`, `--show`), which names the cut and opens no socket. It is kept, never deleted.

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
| `src/Graal531.dpr` | the shell: no arguments opens the start screen (64 with no display); `--show` prints the cut and the token |
| `tests/TestLate531.dpr` | the cut, the login token, the newline rule, the flush order, and the length header |

## On Quattro

5.30r3 and 5.31r4 share this folder, and Quattro (`common/cpp/quattro`)
runs them as a game session. The framing the scaffold reads (opcode plus
32, the body and a newline; the 2-byte length and its long form) is the
gen-5 codec's, and the lab decoded every frame of these builds with the
gen-5 cipher and compression byte (Graal_analysis
`protocol/v5v6-windows-unpacked.md`, "Cipher and framing"), then logged
them in to GServer-v2 and walked after the warp (`v5v6-lab-play.md`). So
the row is 5.24r4's with:

- the token `G3D26090`;
- the receive switch 5.24's without 41 and 181 (95 ids);
- no tiles in Login mode before the 178 warp, only chests and image NPCs.

`Graal531` passes `--server`, `--account`, `--password-env` (default
`GRAAL_PW`, handed over in the environment), `--server-name`, `--level`,
`--x`, `--y`, `--data` and `--seconds` on to `quattro-play --build 5.31r4`,
and the Seihai secure login follows the player's setting. Without
`quattro-play` (or on Linux without a display) it exits 69. The Pascal
side stays `ScaffoldOnly`, so `scripts/loopback.sh` still skips it.

## Not yet

- [x] ~~A login token, once one is recovered. Do not invent an eight-character literal~~ The login line sends `G3D26090` for 5.30r3 and 5.31r4. The images store no literal.
- [x] ~~Quattro login + level + walk~~ through `quattro-play` (above)
- [ ] Numeric client-to-server opcodes. None were recovered as a fixed list
- [ ] The length-wrap bytes for the two internal opcodes
- [ ] The byte pattern that produces "illegal data (2)"
- [ ] Cipher or compression bytes inside a frame
- [ ] The local server-to-client switch, and any property id
- [x] ~~A window, a player, or a server connection~~ in `quattro-play`
- [x] ~~A start screen, so a no-argument start plays~~ Training and the server list, played in `quattro-play`
- [ ] A side-by-side run against the real 5.31r4 (it needs the clock set back)
