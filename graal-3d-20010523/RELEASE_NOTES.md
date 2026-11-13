# Graal3D, later beta (GR3DV003)

The first rebuild of the later Graal3D beta ("New Graal 3D Beta Version",
the Genesis3D one), in Delphi (Object Pascal). It is the February 2000
Graal3D rebuild with what changed in the beta's login, start window and
server messages. Its Genesis3D renderer and BSP world are not rebuilt: the
stand-in level of the February 2000 rebuild is drawn in their place. It is
early: see "Not yet".

**Login token: read from the binary, not yet seen on the wire.** `GR3DV003` is a string literal in the real beta's exe. The beta has not been run: no archived server accepts it.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

These zips hold no original Graal3D code, meshes, textures or levels. The
client carries a simple stand-in level and player of its own.

## What's new in v0.0.5

- [x] **New client.** The later Graal3D beta has a folder of its own, started from `graal-3d-20000205`. It logs in with `GR3DV003`; the start window has the beta's two buttons (Start, and Start Local for offline play) where its form puts them; packet 0 no longer loads the server's level text, as in the beta, whose world is local.

## Downloads

| Zip | Runs on | Window |
|---|---|---|
| `…-linux.zip` | Linux x86-64 | X11 |
| `…-windows.zip` | Windows, 32-bit | GDI |

Each zip has `Graal3D` (the client) and the build's README.

On Windows the first start may show **"Windows protected your PC"**. That
is SmartScreen meeting an unsigned program it has not seen before, not a
virus warning. Either click **More info**, then **Run anyway** (once), or
unblock the zip before you extract it: right-click it, **Properties**,
tick **Unblock**, **OK**. Then nothing in the folder is asked about again.
See [Windows says "Windows protected your PC"](https://github.com/squirelworks/graal-client-repro#windows-says-windows-protected-your-pc).

## What works

- The start window, "Graal 3D", 433 x 321, on the beta's own start picture,
  with the five fields, Start (336, 240) and Start Local (328, 272).
- Login with `GR3DV003`, account and password, in the February 2000 layout
  (the beta's login builder is the same code).
- Online, the local world is loaded at start and kept; the server's level
  name is kept, its level text ignored; everything else as February 2000.
- Offline play (Start Local or `--offline`) on the stand-in level.

## Not yet

The Genesis3D world (`genvs.bsp`), the actor (`dema.act`), blob shadows,
moving platforms, the driver picker, joystick input and the new physics
keys of `graal3dconfig.txt`. See the build's README.

## Checks behind this release

The test suite (109 checks) runs with range and overflow checks and the
heap tracer, and must end with no unfreed memory. CI walks the stand-in
level offline. It does not log into the Graal3D reference server, which
(as the archived server) turns `GR3DV003` away.
