# Graal Worlds 614

Worlds build 614 (plugin FileVersion 6.114). The original is a Unity player plus a
native plugin. This folder builds a portable C# stand-in that loads a
local yard, walks it, and talks to a local-only server on loopback. The
Unity player was not built.

**Login token: none.** The original sends no version token, so there is nothing to check here.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to Graal Online, Cyberjoueurs,
> or Stéphane Portha ("unixmad").

## What's new in v0.0.4.2

- The folder is now `graal-worlds-614-20240421`, named for the build
  and its date. 6.114 is the plugin's version, shared by builds 548 to
  614, and the build stores no token.
- `worlds-player` loads `worlds/local-yard.txt`, moves with collision, and
  opens a local-only session on `127.0.0.1`. The connector hello is the
  eight bytes `GNP1905C`. It is not marked provisional. Lines after the
  hello start with `LOCAL` and are not a 6.114 wire map. The password is
  not logged. No Unity editor was available, so this is not a Unity build.
- `worlds-host` sends only that eight-byte hello. It no longer sends a
  6.0x type-5 zlib login. It lists `Flavor0` and does not call it.
- The build 614 assembly dump is not stored as a name table. The folder
  keeps the counts (6 Quattro, 80 Unity, 10 runtime, 11 plugin,
  1 generated) and two Quattro names.
- On macOS, `worlds-player` starts through the `dotnet` muxer so
  `--self-check` runs. The native app host does not find `libhostfxr`.

## What's new in v0.0.4

- This folder was not in that release.

## Not yet

A Unity player, a 6.114 login frame, the native plugin, Quattro gameplay
types, and the 7.x packet and GS2 notes. See the folder README.
