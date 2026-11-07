# game-tge

**Stock** TGE demo game layer. `ShapeBase`, `Player`, `AIPlayer`, wheeled / flying / hover vehicles, `Item`, `Projectile`, triggers, lightning, precipitation. `Camera` is named with that layer in 3.04 and is still a name on the 5.0.0.7 3D DLL after `ShapeBase` is gone, so a later `Camera` does not have to live in this unit.

What it has to do later: nothing for the shipped 3.04 menus. The classes are in the binary and the 2D scripts do not construct them. A 4.04r2 3D host still has this layer (datablocks included). By 4.2.0.8 the 3D DLL has replaced it with `gameobject`.

| Version | Linked? |
|---|---|
| 3.04 | Yes. `ShapeBase` is the large console class. `Player`, `AIPlayer`, `Item` and the vehicle classes are present. Unused by the shipped 2D scripts. |
| 3.153 | Yes. Same engine, plus that build's extra shape loaders. Still not `GameObject`. |
| 4.04r2 3D | Yes. Near-stock: `Player`, `AIPlayer`, `Item`, `Projectile`, vehicles, triggers, and the matching datablocks. |
| 4.2.0.8 launcher | No. |
| 4.2.0.8 engine | No. The 3D classes are the other DLL. |
| 4.2.0.8 3D | No. `ShapeBase` does not occur. Neither does a Torque `Player` class. |
| 5.0.0.7 launcher | No. |
| 5.0.0.7 engine | No. `ShapeBase` is absent. |
| 5.0.0.7 3D | No. `ShapeBase`, `PlayerData` and `GameBase` are absent. No datablock download phase. |
| 5.30 / 5.31 | No. |
| 6.x | No. Not a residual name. |
