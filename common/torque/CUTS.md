# Cut line

Who links which module. A cell is **yes** only when that binary's note names the surface. **no** means the note says it is absent. **—** means that note does not name it, so the manifest does not link it. **names** means the identifier remains and this unit is not linked.

Lists live in `manifests/`. They are not passed to fpc. 3.04 lists the full 3.x set. 4.x drops the console from the 2D engine and, by 4.2.0.8, drops the stock TGE game layer from the 3D DLL. 5.0.0.7 is still that three-program split. Unpacked 5.30/5.31 omit every module. 6.x is not this tree.

| Module | Kind | 3.04 | 4.04r2 3D | 4.2.0.8 launcher | 4.2.0.8 engine | 4.2.0.8 3D | 5.0.0.7 launcher | 5.0.0.7 engine | 5.0.0.7 3D | 5.30 / 5.31 | 6.x |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `console` | stock | yes | no | no | no | no | no | no | no | no | no |
| `sim` | stock | yes | yes | no | no | yes | no | no | yes | no | no |
| `gui` | patched | yes | yes | no | yes | yes | no | yes | yes | names | names |
| `actionmap` | stock | yes | yes | no | no | — | no | no | yes | no | no |
| `gbitmap` | stock | yes | yes | no | yes | — | no | yes | yes | no | no |
| `math` | stock | yes | — | no | yes | — | no | yes | yes | no | no |
| `game-tge` | stock | yes | yes | no | no | no | no | no | no | no | no |
| `gameobject` | Graal-only | no | no | no | no | yes | no | no | yes | no | no |
| `net-torque` | patched | yes | yes | no | no | yes | no | no | yes | no | no |
| `guigraal` | Graal-only | yes | — | no | yes | — | no | yes | names | names | names |

3.153 links the same modules as 3.04. Two differences, both inside units already linked: `GuiGraal3DCtrl` exists, and `GameConnection` speaks Graal's protocol rather than the Torque demo. `GameObject` is not a 3.153 class.

The 4.04r2 2D engine matches `manifests/4.2.0.8-engine.list` (GUI, `GBitmap`, `GuiGraalCtrl` / `GuiGraal3DCtrl` names; no `SimObject`, no `ActionMap`, no `.dso`). Its launcher matches the empty launcher list: DirectDraw, no Torque class names. Those two 4.04r2 files are not duplicated.

`manifests/4.04r2-g3d.list` is the early 4.x 3D DLL: stock `Player` / `ShapeBase` / vehicles, no `GameObject`. `manifests/4.2.0.8-g3d.list` is the other way round.

5.0.0.7 does not drop a module that 4.2.0.8's 2D engine links. The 3D DLL's own note names `ActionMap`, `GBitmap` and `MatrixF`, which the 4.2.0.8 3D note does not, so that list is longer. The omission past 4.x is the next cut: unpacked 5.30r3 and 5.31r4 are one `quattro_lib` executable. `graal_set`, `SimObject` and `GameConnection` are gone, and so are `ShapeBase`, `ActionMap` and `.dso`. `manifests/5.30.list` links nothing.

6.x is the same kind of program (`quattro_lib` on unpacked Windows 6.00), not a thinner Torque. `manifests/6.x.list` links nothing. `GuiGraalCtrl` and `GuiGraal3DCtrl` are still names the GUI walk compares. That column is residual names, not `TqGui` or `TqGuiGraal`.

`GBitmap` in the marker scan is zero from the unpacked 5.24r3 executable onward, including 5.31 and the 6.x columns, so `gbitmap` is **no** there rather than a leftover name. `Point2I` and `MatrixF` are not among the GUI names 5.30, 5.31 or unpacked 6.00 keep.

Scene types that travel with `sim` on a 3D DLL (terrain, interiors, DTS where named, water, sky, editors) are not their own directories. See `sim/README.md`.
