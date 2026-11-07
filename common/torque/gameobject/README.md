# gameobject

**Graal-only.** `GameObject` is registered under that name. Its constructor calls the `SceneObject` constructor, then installs `GameObject`'s own table. `SceneObject` is stock TGE; the class Graal added is not. It is the replacement for `game-tge`, not a patch of `Player`.

What it has to do later, on the 3D DLL only:

- Exist as a `SceneObject` with the property surface the 4.2.0.8 note lists: shape and nickname, motion and collision, terrain and liquid, mounting, interior queries, and the controlling client. `onRemove` is an event name on the same object.
- Be created when a show-image is given a shape and the host slot `graal_setCreateGraal3DGameObject` is set. An empty slot returns nothing and the assignment stops. The slot itself is the engine/launcher callback, not this class.
- On 5.0.0.7, also the Graal shape classes that note names: `GameShape`, `GameShapeDTS`, `GameShapeDIF`, `GameShapeFT`. The token `GameShape3DS` is absent there. DTS sequences (`TSShape`) stay with `sim`'s scene note.

Not this unit: `TShowImg` and the rest of the `graal/` draw types. Those are C++ in the 2D engine, not Torque console classes.

| Version | Linked? |
|---|---|
| 3.04 | No. Graal's game is `GuiGraalCtrl`, beside stock TGE. |
| 3.153 | No. The `GameObject` world is later (4.20 and the 5.12 model). |
| 4.04r2 3D | No. That DLL still has `game-tge`. |
| 4.2.0.8 launcher | No. |
| 4.2.0.8 engine | No. `GameObject` appears only as the create-object host callback. |
| 4.2.0.8 3D | Yes. |
| 5.0.0.7 launcher | No. |
| 5.0.0.7 engine | No. Same split: the setter name, not the class body. |
| 5.0.0.7 3D | Yes. `GameObject` and `SceneObject`, plus the `GameShape*` names above. |
| 5.30 / 5.31 | No. `GameObject` is absent. |
| 6.x | No. Not a residual name. |
