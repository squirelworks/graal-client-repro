# Graal Worlds 6.114

The Worlds host whose FileVersion is 6.114. The original is a Unity player
with an IL2CPP `GameAssembly` and a native Graal plugin beside it. This
folder does not build that player, does not load the plugin, and does not
add Torque.

The thin host sends `GNP1905C` and marks those bytes provisional. They
are the 6.1.1.3 connector token. The 6.114 dump did not store a clear
login literal. The frame is login-shaped. It is not a 6.114 wire map.
The one native export name this folder lists is `Flavor0`.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to Graal Online, Cyberjoueurs,
> or Stéphane Portha ("unixmad").

## What was read

IL2CPP assembly dumps of the same host, several builds, of which 614 is
the primary one. Roles come from the assembly names and from which kinds
of types the dump contained. The gameplay assembly's type bodies were not
recovered, so they are not named. The name list itself is not stored here.

Build 614 had 108 assemblies: 6 Quattro, 80 Unity, 10 runtime, 11
third-party plugins, and 1 generated image. Other builds of the same host
add or drop a handful of Unity and plugin names. One of them adds a
Firebase set. Those name lists are not copied here.

The two Quattro names this folder keeps are `Assemblies-Quattro.dll`
(gameplay; type bodies not recovered) and `Assemblies-graalunity.dll`
(the C# side of the native bridge). The native plugin is a separate DLL,
not one of the assemblies. This host does not call it.

Unity hosts in those dumps move from 2021.3 through 2023.2. IL2CPP
metadata stays at v29. This folder does not invent an IL2CPP player.

## Programs

| Program | What it does |
|---|---|
| `src/worlds_host.cpp` | the thin host `worlds-host`. Point it at loopback on a lab port. It sends one provisional login-shaped frame, lists `Flavor0`, and logs the frame. Unknown calls log and return. `--list` prints this summary |
| `src/ModulesWorlds.pas` | the dump counts, the two Quattro names, and the connector token |
| `src/GraalWorlds.dpr` | a side shell: no arguments prints one line; `--list` prints the summary |
| `tests/TestWorlds.dpr` | the counts add up, the token is `GNP1905C`, and the dump is not stored as a name table |

`scripts/build.sh` compiles `worlds_host.cpp` with the system C++ compiler
and zlib. A Windows runner without that compiler still builds the Pascal
shell and skips `worlds-host`.

## Running it

```
GRAAL_PW=... build/graal-6.114-worlds/worlds-host \
  --port 14802 --account NAME
```

The host connects only to the loopback address. A connection that
sends the frame is enough. A finished login is not claimed.
`scripts/loopback.sh` points this host at loopback the same way and does
not require the server to accept the login.

`--call NAME` logs `unknown call NAME` and returns. Bytes the peer sends
back are logged the same way and are not parsed.

## Not yet

- [x] The thin host sends a provisional login-shaped frame to loopback
  and lists the native export `Flavor0`. The token bytes are `GNP1905C`
  from the 6.1.1.3 connector note.
- [ ] A login token recovered from the 6.114 host itself.
- [ ] The native Graal plugin (netcode, framing, scripts). Unknown calls
  log and return.
- [ ] Quattro gameplay types.
- [ ] Any packet id, opcode, or script body. The first frame is a
  login-shaped frame, not a 6.114 wire map.
- [ ] A window and a player.
