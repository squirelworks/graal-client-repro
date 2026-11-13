# Graal3D, later beta (`graal-3d-20010523`, `GR3DV003`)

A rebuild of the later **Graal3D** beta, "New Graal 3D Beta Version", in
Delphi (Object Pascal). The original keeps the network side of the
February 2000 Graal3D and swaps its renderer for Genesis3D, with a local
BSP world. This folder starts as a copy of `graal-3d-20000205` and changes
what the static read of the beta found. This is the 0.0.1 reproduction:
hit or miss.

**Evidence: real binary, read statically.** `Graal3D.exe`, 630,272 bytes,
SHA-256 `7c6bb8e8b1dd10620f9b12f108accd274bd436016a00433e256d2ec7bfd9562c`
(Batch-1, from the owner's archive). `GR3DV003` is a string literal in it
(graal_analysis `client-internals/version-token-catalogue.md`, grade B).
It has not been run: no server that accepts `GR3DV003` exists, and it
needs `genesis.dll`.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

This folder holds no original Graal3D code, meshes, textures or levels.

## Folder name

As for `graal-3d-20000205`, the version string names the protocol, not a
build, so the folder carries a date. Both exes carry the same Delphi linker
stamp, so the PE header does not date the beta; the date is the exe's file
date in its archive, 2001-05-23.

## Sources

| What | Where |
|---|---|
| The program | "New Graal 3D Beta Version.rar" (1,998,422 bytes): `Graal3D.exe`, `Genesis.dll` and its drivers, `genvs.bsp`, `dema.act`, the HUD bitmaps, `startscreen.jpg`, `graal3dconfig.txt` |
| What changed from February 2000 | graal_analysis `graal3d/beta3-genesis.md` (static read: imports, strings, the login builder, the packet and property dispatchers) |
| The start window | the beta's own TConnectFrame form, read from its resources for this folder (sizes and places only) |
| Everything carried over | `../graal-3d-20000205/README.md` |

## What differs from the February 2000 rebuild

| | February 2000 (`GR3DV002`) | Later beta (this folder) |
|---|---|---|
| Version string | `GR3DV002` | `GR3DV003` |
| Start window buttons | "&Start" (336, 272, 75 x 28) | "&Start" (336, 240, 75 x 28) and "Start Local" (328, 272, 89 x 28), which plays offline |
| Packet 0 | the level as `.x` text, loaded | clears the leader flag only; the text is ignored |
| World | the server's level | the local world, loaded at start (the beta's `genvs.bsp`; the rebuild uses its stand-in level) |
| Start picture, icon | from the February exe | from the beta exe, byte-identical |

The login layout, port 14901, the frame and text codec, the receive switch
(ids 0, 1, 2, 3, 4, 5, 6, 8 and 100) and the props parser are unchanged,
as the read found.

## Units

As in `graal-3d-20000205`. `src/Connect3D.pas` has the beta's two buttons;
`src/Client3D.pas` ignores the level text; `src/Graal3D.dpr` loads the
local world online too. `loopback3d.sh` is not carried over: the reference
server rejects `GR3DV003`.

## Running it

```
Graal3D                                                     # start window
GRAAL_PW=guest Graal3D --server HOST[:14901] --account guest --window
Graal3D --offline --window                                  # the stand-in level
```

## Not yet, or not known

- [ ] The Genesis3D world: `genvs.bsp`, its entities (`MovingPlat`, `DeathMatchStart`) and the Genesis3D world collision.
- [ ] The player as the Genesis3D actor `dema.act`, with the `shadow.bmp` / `shadowalpha.bmp` blob shadows.
- [ ] The HUD bitmaps (`font.bmp`, `chatbar.bmp`, `corona.bmp`, `corona_a.bmp`).
- [ ] The driver and mode picker (TDriversForm), DirectInput joystick and force feedback.
- [ ] The new `graal3dconfig.txt` keys (`RUN_SPEED`, `WALK_SPEED`, the frictions, gravity, jump thrust, camera distances, `playerscale`); their built-in defaults are not read.
- [ ] The beta's built-in default host (not reproduced).
- [ ] The UDP datagram layout compared byte for byte with `GR3DV002`.
- [ ] A lab run: needs `genesis.dll` (in the RAR) and a server that accepts `GR3DV003`.
- [ ] Everything still missing from `graal-3d-20000205`.
