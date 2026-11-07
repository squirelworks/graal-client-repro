# sim

**Stock** TGE. `SimObject`, `SimSet`, `SimGroup`: ids, names, dynamic fields, groups, `delete`.

What it has to do later: be the object model the console (3.x) and the 3D DLL (4.x/5.0) sit on. It does not become `GameObject` (`gameobject`) and it does not become `ShapeBase` (`game-tge`).

Scene classes that the notes keep beside `SimObject` are this module's neighbours, not new directories:

- 3.04 compiles terrain, interiors, DTS shapes, sky, water, and the world and terrain editors. The shipped 2D scripts do not use them.
- 4.2.0.8 3D names `SimObject` (including `delete`) and `TerrainBlock`, streams terrain chunks, and reads interiors. It does not name `TSShape`.
- 5.0.0.7 3D names `SimObject`, `SimSet`, `SimGroup`, `TerrainBlock`, `TerrainEditor`, `WaterBlock`, `Camera`, `fxSunLight`, `TSShape`, and interior queries. `Sky` and `Sun` are absent. The class names `OpenGLDevice` and `D3DDevice` are absent.
- 4.04r2 3D is near-stock, so those scene classes are present with the TGE game layer (`game-tge`).

| Version | Linked? |
|---|---|
| 3.04 | Yes. |
| 3.153 | Yes. |
| 4.04r2 3D | Yes. |
| 4.2.0.8 launcher | No. |
| 4.2.0.8 engine | No. The note says no `SimObject` and no `SimGroup`. |
| 4.2.0.8 3D | Yes. |
| 5.0.0.7 launcher | No. |
| 5.0.0.7 engine | No. The note lists `SimObject` as absent. |
| 5.0.0.7 3D | Yes. |
| 5.30 / 5.31 | No. |
| 6.x | No. Not a residual name of this unit. Unpacked 6.00 has no `SimObject`. |
