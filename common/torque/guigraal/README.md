# guigraal

**Graal-only.** `GuiGraalCtrl` is the 2D game as one GUI control. `GuiGraal3DCtrl` is the later sibling. Neither is stock TGE. The `graal/` types (`TDrawableObject` and the types under it, `TGraalConnection`) are C++ inside the game. They are not console classes and this module does not expose them to script.

What it has to do later, for 3.04: the 31 methods below, each registered with an empty usage string. The count includes the command name and the object. `moveUp` takes one script argument. `openServerList` takes none. `loadLevel` takes three. `updatePlayerProfile` takes ten.

| Method | Script arguments |
|---|---|
| `moveUp`, `moveLeft`, `moveDown`, `moveRight` | 1 |
| `doA`, `doS`, `doD`, `doQ`, `doP`, `doM` | 1 |
| `doMicro` | 1 |
| `setChat` | 1 |
| `setPassWord` | 1 |
| `openServerList` | 0 |
| `selectServer` | 1 |
| `selectServerCategory` | 1 |
| `startOfflineMode` | 0 |
| `connectToSelectedServer` | 0 |
| `serverDirectConnect` | 1 |
| `privateMessageSend` | 0 |
| `playerListOpenPlayer` | 1 |
| `playerListProfile` | 1 |
| `updateLoadLevelFields` | 0 |
| `loadLevel` | 3 |
| `updatePlayerProfile` | 10 |
| `updatePlayerMuted` | 1 |
| `updateMidiVolume`, `updateMp3Volume`, `updateRadioVolume`, `updateMicroActivationLevel`, `updateGraalOptions` | 0 |

`setNickName`, `setAccountName`, `setLanguage` and `retrieveAccountFields` are not on the 3.04 table. Nickname, account and language are `$pref::Graal::` variables. Those four methods are 3.153's.

`GuiGraal3DCtrl` is not a console class in 3.04. It is a name from 3.153 on.

| Version | Linked? |
|---|---|
| 3.04 | Yes. `GuiGraalCtrl` only. The shipped control is named `Adventure`. |
| 3.153 | Yes. Both names. The four account methods above are this build's, not 3.04's. |
| 4.04r2 3D | Not on the list. The marker scan hits `GuiGraal3DCtrl` in the 3D DLL and `GuiGraalCtrl` in the 2D engine. The 2D engine list is the one that links this unit. |
| 4.2.0.8 launcher | No. |
| 4.2.0.8 engine | Yes. Both names are engine types. While a script class is being resolved, a class named `GuiGraalCtrl` or `GuiGraal3DCtrl` is discarded, so script does not construct either. The 31-method table is not claimed for this DLL. |
| 4.2.0.8 3D | Not on the list. The 3D note does not name the control. The 2D engine owns the type. |
| 5.0.0.7 launcher | No. |
| 5.0.0.7 engine | Yes. The note lists `GuiGraalCtrl` and `GuiGraal3DCtrl` among the Graal types that DLL defines. |
| 5.0.0.7 3D | The name `GuiGraal3DCtrl` is a string in that DLL. The unit stays on the engine list, not a second copy. |
| 5.30 / 5.31 | Residual names, not this unit. Both `GuiGraalCtrl` and `GuiGraal3DCtrl` remain. `graal_set` is gone. |
| 6.x | Residual names, not this unit. Unpacked 6.00's GUI walk compares a control with `GuiGraalCtrl` and with `GuiGraal3DCtrl` and drops either when a parent flag is clear. There is no Torque scene behind the 3D name. |
