# actionmap

**Stock** TGE. `ActionMap`: bind, bindCmd, push, pop, save. In 3.04 the shipped `moveMap` turns keys into `Adventure.moveUp` and the other `guigraal` calls. This unit is only the map. The Graal methods are `guigraal`.

| Version | Linked? |
|---|---|
| 3.04 | Yes. Eleven methods on the console class. `AdventureGui::onWake` pushes `moveMap`. |
| 3.153 | Yes. |
| 4.04r2 3D | Yes. The marker scan hits `ActionMap` in that DLL. |
| 4.2.0.8 launcher | No. |
| 4.2.0.8 engine | No. The marker scan is zero, and the engine note has no `ActionMap`. Keys arrive as `invokeGraalKeyboardEvent` into `GuiCanvas`. |
| 4.2.0.8 3D | Not on the list. `torque/4208-g3d.md` does not name `ActionMap`. |
| 5.0.0.7 launcher | No. |
| 5.0.0.7 engine | No. The note lists `ActionMap` as absent. |
| 5.0.0.7 3D | Yes. `ActionMap`, `ActionMapGroup`, `GlobalActionMap`, `ActiveActionMapSet`. |
| 5.30 / 5.31 | No. |
| 6.x | No. Not a residual name. |
