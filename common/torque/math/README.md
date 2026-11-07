# math

**Stock** TGE. `Point2I` and `MatrixF`.

What it has to do later: the 2D integer point and the 3D matrix the engine already calls. The 2D matrix stack pushed through `graal_set` (`graal_setPushGraal2DMatrix` and its siblings) is a host callback, not this unit.

| Version | Linked? |
|---|---|
| 3.04 | Yes. Full TGE, so the math types the later 2D engine still exports are in this binary too. |
| 3.153 | Yes. Same monolith. |
| 4.04r2 3D | Not on the list. The 3D note names the game layer, not `Point2I` or `MatrixF`. |
| 4.2.0.8 launcher | No. |
| 4.2.0.8 engine | Yes. The engine note names `Point2I`. `MatrixF` is part of the same era-B engine description (`study-torque-clients.md`). |
| 4.2.0.8 3D | Not on the list. `torque/4208-g3d.md` does not name `Point2I` or `MatrixF`. |
| 5.0.0.7 launcher | No. |
| 5.0.0.7 engine | Yes. The note names `MatrixF`. |
| 5.0.0.7 3D | Yes. The note names `MatrixF`. |
| 5.30 / 5.31 | No. |
| 6.x | No. Not a residual name. |
