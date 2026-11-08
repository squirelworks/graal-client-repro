# Graal Worlds 6.114

The Worlds host, FileVersion 6.114. The original is a Unity player plus a
native plugin. This folder builds a portable C# stand-in that loads a
local yard, walks it, and talks to a local-only server on loopback. The
Unity player was not built.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to Graal Online, Cyberjoueurs,
> or Stéphane Portha ("unixmad").

## What's new in v0.0.5

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

## What's new in v0.0.4

- This folder was not in that release.

## Not yet

A Unity player, a 6.114 login frame, the native plugin, Quattro gameplay
types, and the 7.x packet and GS2 notes. See the folder README.
