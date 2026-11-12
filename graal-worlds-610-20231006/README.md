# Graal Worlds 610 (scaffold)

Setup name `WorldsSetup64-610`.

The original is a Unity player (`Worlds.exe`) with an IL2CPP
`GameAssembly.dll` and the native Graal3D plugin beside it. This folder
does not build that player, does not load the plugin, and does not speak
to a server.

No eight-character token is stored in this build. A case-sensitive search
for `G3D`, `GNP`, `GNW` and `G2N` tokens in the exe, GameAssembly, every
plugin and `global-metadata.dat` found none. Like the other tokenless
folders, this one is named for its build and its date:
`graal-worlds-610-20231006`.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to Graal Online, Cyberjoueurs,
> or Stéphane Portha ("unixmad").

## What was read

| Fact | What the image shows |
|---|---|
| Build | `610` |
| Unity bundleVersion | 610 |
| Unity | 2022.3.9f1 |
| Plugin | `Graal3DEngine.dll`, FileVersion 6.114 |
| Build date | 2023-10-06 (GameAssembly time stamp) |
| Company / product | `toonslab` / Graal Worlds |
| Token | None stored |

The playable Worlds stand-in lives in
[`graal-worlds-614-20240421`](../graal-worlds-614-20240421/). Every Worlds
folder is v7 and does not block CI (`scripts/v7.sh`).

## Units

| Unit | What it does |
|---|---|
| `src/Worlds610.pas` | the facts above |
| `src/GraalWorlds610.dpr` | the shell: no arguments exits 0; `--show` prints the facts |
| `tests/TestWorlds610.dpr` | checks the facts and that no token is stored |

## Not yet

- [ ] A login token, if one is recovered. Do not invent one
- [ ] Anything on the wire
- [ ] A window, a player, or a server connection
