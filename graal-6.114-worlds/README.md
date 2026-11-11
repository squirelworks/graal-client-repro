# Graal Worlds 6.114

The Worlds host whose FileVersion is 6.114. The original is a Unity player
with an IL2CPP `GameAssembly` and a native plugin beside it. This folder
does not build that Unity player, does not load the plugin, and does not
add Torque.

`GNP1905C` is the documented connector token. A running 6.113 client sends
those eight bytes before it reads the server. This folder does not mark
that token provisional. The 6.114 image was not shown to store the literal,
and the bytes after the hello in the 6.113 capture are unidentified
ciphertext, so nothing here continues that capture. The folder name stays
`graal-6.114-worlds`.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to Graal Online, Cyberjoueurs,
> or Stéphane Portha ("unixmad").

## Unity

No Unity editor is installed in the environment that built this folder.
`unity`, `unity-editor`, and `Unity` are not on `PATH`, and nothing under
`/opt` or `~/.local` is an editor. No editor version is selected. The
Unity player was not built. A passing self-check, a log line, or the PPM
raster is not a Unity player build.

The playable stand-in is portable C#, compiled with Mono `mcs` 6.8 when
`dotnet` is absent. It does not reference `UnityEngine`.

## What is verified

The connector hello is the eight ASCII bytes `GNP1905C`, written before
any read. That is the clear prefix of the 6.113 port-14900 capture. It is
not a 6.114 login line, not a packet id, and not a claim that every v7
build sends the same bytes.

## What is local-only

The yard, the colours, the camera, the input steps, the collision, and
every line that starts with `LOCAL` are a fixture for this repo. They are
not a v7 wire map and not 6.114 compatible. The entity's one-cell step is
part of that fixture.

`worlds/local-yard.txt` is the local yard. `#` is solid, `.` is open, `@`
is the player start, `E` is the fixture entity. Colours in that file are
the only art, drawn into a PPM at smoke time.

After the eight-byte hello the lab session is:

```
LOCAL login account=NAME password-length=N
LOCAL ok session
LOCAL enter
LOCAL enter world=local-yard x=1 y=1
LOCAL entity id=1 x=7 y=3
LOCAL move dir=e
LOCAL you x=2 y=1 blocked=0
LOCAL entity id=1 x=6 y=3
```

The password is never written and never logged. A host other than
`127.0.0.1` is refused before a socket opens. States are `Connecting`,
`HelloSent`, `Session`, `InWorld`, and `Error` with a short reason.

## Programs

| Program | What it does |
|---|---|
| `player/` | portable player: yard, movement, collision, camera, input, local session |
| `worlds/local-yard.txt` | local-only yard |
| `smoke.sh` | builds if needed, then runs the smoke on `127.0.0.1` |
| `src/worlds_host.cpp` | sends only the eight-byte hello. Lists `Flavor0` and does not call it |
| `src/ModulesWorlds.pas` | dump counts, two Quattro names, connector token, `Flavor0` |
| `src/GraalWorlds.dpr` | side shell. No socket |
| `tests/TestWorlds.dpr` | counts, token, and that the dump is not a name table |

`scripts/build.sh` compiles the Pascal shell, `worlds-host` (no zlib), and
`worlds-player` with `dotnet` or `mcs`. Linux fails the build if neither
C# compiler exists. Windows and macOS still build the Pascal shell when
the C# compiler is missing. Windows does not build `worlds-host`; that
connector uses POSIX sockets. On macOS a `dotnet` build is started with
`dotnet worlds-player.dll`. The native app host does not find
`libhostfxr` on that system.

## Running it

```
graal-6.114-worlds/smoke.sh 14923
```

The same program directly:

```
GRAAL_PW=loopbackpw build/graal-6.114-worlds/worlds-player \
  --smoke --port 14923 --account loop1 \
  --world graal-6.114-worlds/worlds/local-yard.txt \
  --raster build/graal-6.114-worlds/local-yard.ppm \
  --moves e,e,e,s,e
```

`--self-check` runs the portable tests. `--serve --port 14923` waits for
one local client. `worlds-host --port 14923 --account loop1` sends the
eight-byte hello and stops.

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
(the C# side of the native bridge). The native plugin is a separate DLL.
This folder lists the export name `Flavor0` from build 71243 and does not
call it. Builds 548 through 614 use an obfuscated name that was not
recovered.

Unity hosts in those dumps move from 2021.3 through 2023.2. IL2CPP
metadata stays at v29. This folder does not invent an IL2CPP player.

`Graal_analysis` has a cleaned 7.x protocol note (classic ids, gen-5
framing, a server-defined header, optional RC4 or AES, GS2). This player
does not implement that note. No 6.114 capture here confirms those fields,
and the 6.113 capture does not show them in the clear.

## Not yet

- [x] Connector token `GNP1905C`, not marked provisional.
- [x] Portable player: local yard, camera, input, movement, collision, and a loopback session with one updating entity. Local-only after the hello.
- [ ] A Unity editor build. No editor was installed, so the Unity player was not built.
- [ ] A 6.114 login frame. The 6.113 header, zlib block, and ciphertext are not reproduced.
- [ ] TODO: the connector login (signed `conf.gs`, then `setProtocol("EILLLT")`, `sendRaw`, `setEncryptionOut`) is pending verification on a real Worlds client. It was verified only on the 6.11 desktop clients, so it is scaffolded only in `graal-6.1.1.3-GNP1905C` (with the placeholder token `SEI00001`). This folder does not use it until a live Worlds trace confirms it.
- [ ] The native plugin. `Flavor0` is named and not called.
- [ ] Quattro gameplay types.
- [ ] Packet ids, opcodes, ciphers, asset formats, and GS2 from the 7.x notes.
- [ ] Graal tiles, ganis, or levels from an install.

## Unsupported

Unity scene and input, IL2CPP, Torque, the native plugin, gen-5 framing,
the 6.0x type-5 login, the 6.113 header and ciphertext, RC4, AES, classic
PLO and PLI ids, GS2, a real password check, and any asset from a Graal
install.
