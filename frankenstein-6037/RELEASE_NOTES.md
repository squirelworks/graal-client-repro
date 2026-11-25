# Frankenstein 6.037 (v6.037 + v5.120 Graal3D, from the 5.12 repro)

Community experimental client. Releases use the tag prefix
`frankenstein-6037-v` from `.github/workflows/frankenstein-6037.yml`. They
are a separate series from the combined graal-client-repro release and
from the `frankenstein-v` series.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

## Unreleased

- The 3D world is drawn by the 5.12 repro's renderer while the server names
  a Camera: sky, `.3ds`, `.dts` and `.dif` shapes from `levels3d/`, the
  streamed terrain, water and name tags, lit and moved as the lab saw the
  real 5.12 do. The stand-in view remains for a server with no Camera.

## What's new in frankenstein-6037-v0.0.1

- The first client: `frankenstein-6037` for macOS, Linux and Windows. The
  6.03r7 Quattro program (6.03r7 token and login tail per platform) with
  the 5.12 repro's Graal3D link built in.
- A `3 ` server, picked with `--server-name` or reached by the Login
  server's 178 warp, is entered as 5.12 entered it: the Torque link over
  UDP to the listed port + 1, then the TCP login. The link runs to login
  step 6 and keeps the player's object, its movement and the other ghosts;
  server text goes to the 6.x GS2 machine and its triggers come back as
  `events`.
- A stand-in 3D view once the link is up (sky colour, ground grid, a box
  per object, the 6.x frame as an inset). `--no-3d-view` turns it off.

## Not yet

- The real Torque world (terrain, interiors, shapes, sky textures); keys
  moving the player in 3D; the 6.x start screen and server list; a lab run
  against the Seihai gserver's `graal3d` mode.
