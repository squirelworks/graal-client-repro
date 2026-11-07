# Graal Worlds 6.114 (scaffold)

Empty shell for the Worlds host whose FileVersion is 6.114. The original
is a Unity player with an IL2CPP `GameAssembly` and a native Graal plugin
beside it. This folder does not build that player, does not load the
plugin, and does not speak a protocol.

The wire token was not stored as a clear eight-character literal, so this
folder is not `graal-6.114-<token>`. Nothing here invents one.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to Graal Online, Cyberjoueurs,
> or Stéphane Portha ("unixmad").

## What was read

Six IL2CPP assembly dumps of the same host, builds 548, 610, 612, 613, 614
and 71243. The catalogue in `src/ModulesWorlds.pas` is build 614, which is
the primary dump. Roles are written from the assembly names and from which
types the dump actually contained. The gameplay assembly's type bodies were
not recovered, so they are not named.

The native plugin is a separate DLL, not one of these assemblies. Builds
548 through 614 publish it under an obfuscated export name and a 6.114
version resource. Build 71243 publishes it as a Flavor0 export name and
does not keep that version resource. This shell does not call it.

Unity hosts, from the same dumps: 548 is 2021.3, 610 is 2022.3, and 612
through 71243 are 2023.2. IL2CPP metadata stays at v29.

## Assemblies

| Kind | What it is for |
|---|---|
| Quattro | `Assemblies-Quattro.dll` (gameplay; type bodies not recovered), `Assemblies-quattroplugins.dll` (sky, planet, mesh files), `Assemblies-Quattroshared.dll` (tiles, lights, warps, editor map objects), `Assemblies-quattrosharedlowlevel.dll` (bundles, streaming files, a cipher helper), `Assemblies-graalunity.dll` (actor data from the native plugin), `Assembly-CSharp.dll` (a small script assembly, not the game) |
| Unity | Engine modules and Unity packages (render pipelines, physics, input, purchasing, services) |
| Runtime | `mscorlib` and the `System.*` libraries, plus `Mono.Security` |
| Plugin | JSON, Cinemachine, PlayMaker and its UI glue, Backtrace, a file browser, a debug console, SharpZipLib, purchasing helpers, Steamworks, LevelPlay |
| Generated | `__Generated`, the IL2CPP generated image |

Names that are not on the 614 list:

| Build | Extra names | Missing from the 614 list |
|---|---|---|
| 548 | `Assembly-CSharp-firstpass.dll`, `clipper_library.dll`, `ConditionalExpression.dll`, `UnityEngine.UNETModule.dll`, `UnityEngine.UIElementsNativeModule.dll`, `UnityEngine.UnityWebRequestTextureModule.dll` | several later Unity modules, the file browser, the debug console, LevelPlay, Steamworks |
| 610, 612 | `Assembly-CSharp-firstpass.dll` | 610 is missing the later 2D and UI modules; 612 is only missing the file browser, `System.Drawing`, LevelPlay and the sprite-mask module |
| 613 | `Firebase.App.dll`, `Firebase.Messaging.dll`, `Firebase.Platform.dll` | LevelPlay |
| 71243 | none | `Unity.Postprocessing.Runtime.dll` |

## Units

| Unit | What it does |
|---|---|
| `src/ModulesWorlds.pas` | the 614 assembly names, a kind, and a one-line purpose |
| `src/GraalWorlds.dpr` | the shell: no arguments exits 0; `--list` prints the catalogue |
| `tests/TestWorlds.dpr` | the catalogue is 614 long, unique, and does not invent a token or a gameplay type list |

## Not yet

- [ ] A login token, once one is recovered from a capture or a clear literal
- [ ] The native Graal plugin (netcode, framing, scripts)
- [ ] Quattro gameplay types
- [ ] Any packet id, opcode, or script body
- [ ] A window, a player, or a server connection
