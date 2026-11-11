# Graal Worlds 7.0.1.7.5.0 (scaffold)

Installer `WorldsSetup64-7.0.1.7.5.0` (version resource 7.0.1.7.5.0). The installed "GraalOnline Worlds" folder is the same build: every shared file matches. The bundleVersion is most likely `701750`; the Unity 6 settings layout was not decoded, so that field is not proven.

The original is a Unity player (`Worlds.exe`) with an IL2CPP
`GameAssembly.dll` and the native Graal3D plugin beside it. This folder
does not build that player, does not load the plugin, and does not speak
to a server.

No eight-character token is stored in this build. A case-sensitive search
for `G3D`, `GNP`, `GNW` and `G2N` tokens in the exe, GameAssembly, every
plugin and `global-metadata.dat` found none. Like the other tokenless
folders, this one is named for its build and its date:
`graal-worlds-7.0.1.7.5.0-20260403`.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to Graal Online, Cyberjoueurs,
> or Stéphane Portha ("unixmad").

## What was read

| Fact | What the image shows |
|---|---|
| Build | `7.0.1.7.5.0` |
| Unity bundleVersion | 701750 (most likely; the Unity 6 field was not decoded) |
| Unity | 6000.0.63f1 |
| Plugin | `Graal3DEngine.dll`, no version resource |
| Build date | 2026-04-03 (GameAssembly time stamp) |
| Company / product | `toonslab` / `GraalOnline Worlds` |
| Token | None stored |

The playable Worlds stand-in lives in
[`graal-worlds-614-20240421`](../graal-worlds-614-20240421/). Every Worlds
folder is v7 and does not block CI (`scripts/v7.sh`).

## Units

| Unit | What it does |
|---|---|
| `src/Worlds70175.pas` | the facts above |
| `src/GraalWorlds70175.dpr` | the shell: no arguments exits 0; `--show` prints the facts |
| `tests/TestWorlds70175.dpr` | checks the facts and that no token is stored |

## Not yet

- [ ] A login token, if one is recovered. Do not invent one
- [ ] Anything on the wire
- [ ] A window, a player, or a server connection
