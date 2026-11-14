# Graal3D (February 2000)

The first rebuild of Graal3D, the 3D Graal side project of February 2000,
in Delphi (Object Pascal). It logs into a Graal3D server, loads the level
the server sends, shows the other players and walks, jumps and chats in 3D.
It is early: see "Not yet".

**Login token: tested against the real client.** The original was run in the lab and `GR3DV002` was seen in its login on the wire (lab run against the test server); this rebuild sends the same token.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

These zips hold no original Graal3D code, meshes, textures or levels. The
client carries a simple stand-in level and player of its own; put your
Graal3D files next to it for the real ones.

## What's new in v0.0.5

- [x] **Back plane 5000.** Nothing beyond 5000 along the view is drawn, the value the real client sets on its viewport (it was 100000). The cloud ceiling now stops where that plane cuts it; a live check that no later call moves the plane is still open.

## What's new in v0.0.4.2

- [x] **The sky.** The level's cloud ceiling is drawn to the horizon, as the real client draws it, instead of a black sky.
- [x] **Logo and nickname banner.** The view carries the real client's black strip across the top with your nickname in large white letters, and the install's `logo.bmp` at its top left.

## What's new in v0.0.4

- Rebuilt from the latest code; the changes for this client are listed here as they land.
- [x] Graal3D's own start window: the wood-board picture taken out of the
  real Graal3D.exe and built into this one, in its own window, "Graal 3D",
  the size of the picture (433 x 321), as the real one.
- [x] The five fields where the real window has them, dark red with white
  text, Server IP as a drop-down box, and one Start button. The Offline
  and Quit buttons of 0.0.1 are gone, as the real window has neither:
  close the window to quit, and `--offline` still walks the default level.
- [x] The game opens in a window of its own, "Graal 3D", 640 x 480, and the
  start window comes back when it ends, as with the real program.
- [x] Graal3D.exe's own icon (the torch) in the title bar and the taskbar.

## What's new in v0.0.3

- Stress tested before release: a long offline run through the stand-in
  level with no crash or error.

## Downloads

| Zip | Runs on | Window |
|---|---|---|
| `…-linux.zip` | Linux x86-64 | X11 |
| `…-windows.zip` | Windows, 32-bit | GDI |

Each zip has `Graal3D` (the client) and the build's README. The test
programs are built and run on every release but no longer shipped.

On Windows the first start may show **"Windows protected your PC"**. That
is SmartScreen meeting an unsigned program it has not seen before, not a
virus warning. Either click **More info**, then **Run anyway** (once), or
unblock the zip before you extract it: right-click it, **Properties**,
tick **Unblock**, **OK**. Then nothing in the folder is asked about again.
See [Windows says "Windows protected your PC"](https://github.com/squirelworks/graal-client-repro#windows-says-windows-protected-your-pc).

## Where to put your Graal3D files

Put them in the same folder as `Graal3D` (on Windows `Graal3D.exe`):

- Unzip `graal-assets.zip` into that folder, so it holds `Graal3D.exe` and
  `graal-assets/` side by side.
- Or copy the contents of the Graal3D archive into that folder: the `.x`
  meshes, the `.bmp` textures and `graal3dconfig.txt`.

Only that folder is read, never the folder above it. `--data DIR` points at
another folder instead.

## Playing

Run `Graal3D` with no arguments for the start window: nickname, server
IP, port (14901), account and password (guest / guest). Start logs into a
Graal3D server; `Graal3D --offline --window` walks the default level.

- Keypad 8 / 2: forward and back. Keypad 4 / 6: step sideways. The arrow
  keys work too.
- Keypad 5: jump. Keypad 0: camera follow on or off.
- Enter: open the chat line, type, Enter to send. Esc: leave the game.

```
Graal3D                                                     # start window
GRAAL_PW=guest Graal3D --server HOST:14901 --account guest --window
Graal3D --offline --window
```

## What works

- Login, the player's own props, other players, the level sent by the
  server (saved next to the program), the administrator message box and
  the disconnect text.
- Position and chat straight to the other players over UDP, or through the
  server with no UDP.
- Walking, running, jumping, the follow camera and collision with the level.
- The player's look from the server: body and head meshes and textures,
  arm, hand and shoe colours.
- The chat log at the bottom left, ten seconds a line.

## Not yet

- [ ] The Hardware options and Player look windows (their settings come
  from `graal3dconfig.txt` for now).
- [ ] Full screen.
- [ ] Arm and leg swing while walking.
- [ ] Saving the nickname between runs.
- [ ] Field text in Windows' MS Sans Serif (Liberation Sans is drawn).
- [ ] The real game window could not be compared: Graal3D.exe needs
  Direct3D Retained Mode (d3drm.dll), which is not available, so its
  size and title come from the form (TAdventure, 648 x 508 with the frame,
  "Graal 3D").

## Checks behind this release

The test suite (107 checks) runs with range and overflow checks and the
heap tracer and must end with no unfreed memory; it includes 2000 damaged
level files read without a crash. CI walks the stand-in level offline on
Linux and Windows, and logs two of these clients into the Graal3D
reference server: both log in, save the level as sent, see each other and
swap a chat line over UDP.
