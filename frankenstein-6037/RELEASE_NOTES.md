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
  real 5.12 do. The stand-in view is gone: until the server names a Camera
  the view is black, as the 5.12's is.
- The draw distance is the player's `visibledistance3D` from a
  `game_config.txt` beside the program or in an asset root (1000 by
  default, at most 2400, as the 5.12).
- First lab run against a real server (seihai-gserver `graal3d`,
  2026-11-26): GS2 timers and walking no longer slow down while the 3D view
  draws (the program keeps its 50 ms tick as its clock; the 3D frame takes
  at most about half the time), and a 3D weapon's `player.position` reads
  the player's own object.
- The player's own 3D object moves with the arrow keys and with a script
  setting `player.position`, and the server and other players see it.
- Shapes and textures a 3D world names are asked for over TCP and kept in
  the install's `levels3d/`, so a fresh install draws the world.
- An OpenGL renderer for the 3D view (OpenGL 3.2 core, the profile macOS,
  Mesa and the Windows drivers all offer; on Apple Silicon Macs Apple runs
  it on Metal). It draws the same frame as the software renderer, through
  the same rules (the conformance worlds match to within 0.01% of the
  pixels), several times faster, and the 3D view is no longer held to the
  6.x program's 50 ms tick: it draws up to 60 frames a second
  (`--max-fps N`, 0 for no cap) while the program keeps its clock.
  `--renderer auto|opengl|software` picks the backend; auto falls back to
  the software renderer when no OpenGL 3.2 context can be made (a Windows
  VM with only GDI Generic 1.1, where Mesa's `opengl32.dll` beside the
  program, or named by `FRANK_GL_LIBRARY`, also serves). Nothing about the
  protocol changes.
- A frame-rate counter in the top-left corner of the 3D view (frames a
  second, the mean draw time, the renderer; `--no-fps` hides it), logged
  every 5 seconds, with a summary at exit.
- `--bench [WORLD]`: the conformance suite's worlds (sky, cube, texture,
  terrain, water, 1024 cubes, grass, and all of them together) drawn
  offline for frame rates, with `--compare` against the software renderer.

- The 5.12's GS2 3D objects on the 6.x GS2 machine: `new GameObject(name)`
  and `player.camera` (the view's Camera, read only) with the
  `GameObject` and `SceneObject` members a weapon3d reads and sets
  (position, x, y, z, scale, transform, rotation, eulerrotation, the
  forward, right and up vectors, the boxes, alpha, nickname, shape and the
  mount and drawn queries), in the 5.12's formats and rotation rules. The
  conformance probe C030 gives back every value the real 5.12 gave.
- `timevar3`, the server's Graal3D clock, advances in 3D weapons.
- GS2 show-images on the screen layer (layer 4 and up) draw over the
  whole 3D view, as GS2 GUIs drew over the 5.12's scene, not only in the
  6.x inset.
- When the server moves the player's own object (a door, a warp in the
  same world), the client reports the new place to the server, as the
  5.12 did.
- 3D files are asked for as the 5.12 asks: images by their bare name,
  and `.cs` and `.ter` names never.

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

- A Metal backend for the 3D view (the renderer interface has room for
  one; OpenGL still runs on current macOS).
- The real Torque world (terrain, interiors, shapes, sky textures); keys
  moving the player in 3D; the 6.x start screen and server list; a lab run
  against the Seihai gserver's `graal3d` mode.
