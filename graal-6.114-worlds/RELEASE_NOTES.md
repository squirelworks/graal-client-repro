# Graal Worlds 6.114

The Worlds host, FileVersion 6.114. The original is a Unity player plus a
native Graal plugin. This folder builds a C++ thin host that sends one
provisional login-shaped frame to loopback. It does not play the game.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to Graal Online, Cyberjoueurs,
> or Stéphane Portha ("unixmad").

## What's new in v0.0.5

- `worlds-host` opens `127.0.0.1` on a lab port and sends one provisional
  login-shaped frame. The token is the Linux 6.03r7 neighbour `G3D0511C`,
  marked provisional. The frame is not a 6.114 wire map. No IL2CPP player
  and no Torque.
- The build 614 assembly dump is no longer stored as a name table. The
  folder keeps the counts (6 Quattro, 80 Unity, 10 runtime, 11 plugin,
  1 generated) and two Quattro names.

## What's new in v0.0.4

- This folder was not in that release.

## Not yet

A recovered login token, the native plugin, Quattro gameplay types, a
window, and a player. See the folder README.
