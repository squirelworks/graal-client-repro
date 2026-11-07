# console

**Stock** TGE 1.2. The script console: namespaces, packages, the native command registry, and loading plain `.cs` and compiled `.dso` v33 (Graal's opcode numbering, big-endian float tables on PPC).

What it has to do, when the hold lifts: boot the way 3.04 boots (`setModPaths`, `exec` of the shipped `main.cs` chain), and expose the stock global commands the shipped scripts call (`echo`, `exec`, `export`, `schedule`, `isObject`, the file helpers). Graal's own calls are `guigraal`, not this unit. The parked `TqCode` / `TqCompile` / `TqVM` units are an unfinished interpreter for this job. They are not wired in, and this stub does not call them.

| Version | Linked? |
|---|---|
| 3.04 | Yes. Full console. The registrar holds 857 functions and methods. Game string `Torque Game Engine Demo`, `getVersionNumber` 1100. |
| 3.153 | Yes. Same monolith, still `.dso` and `exec`. |
| 4.2.0.8 launcher | No. Delphi. |
| 4.2.0.8 engine | No. `Con::` does not occur. No TorqueScript and no `.dso`. |
| 4.2.0.8 3D | No. No `.dso` and no TorqueScript compiler string. `SimObject` in that DLL is `sim`, not a script language. |
| 4.04r2 3D | No `.dso`. A console-prompt string can remain; that is not this unit. |
| 5.0.0.7 launcher / engine / 3D | No. The 3D note lists `.dso` as absent. |
| 5.30 / 5.31 | No. |
| 6.x | No. `quattro_lib` has no Torque console. Not residual names of this unit. |

`engine-and-formats.md` says the 5.12 3D DLL still has a console and that `.dso` is 3.x only. This unit is not on a 5.12 list until that console is read on its own. The 5.12 client is outside the manifests here.
