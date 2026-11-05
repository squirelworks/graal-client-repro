# Graal3D (February 2000)

The first rebuild of Graal3D, the 3D Graal side project of February 2000,
in Delphi (Object Pascal). It logs into a Graal3D server, loads the level
the server sends, shows the other players and walks, jumps and chats in 3D.
It is early: see "Not yet".

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

These zips hold no original Graal3D code, meshes, textures or levels. The
client carries a simple stand-in level and player of its own; put your
Graal3D files next to it for the real ones.

## What's new in v0.0.4

- Rebuilt from the latest code; the changes for this client are listed here as they land.

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
See [Windows says "Windows protected your PC"](https://github.com/squirelworks/graal-delphi#windows-says-windows-protected-your-pc).

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
Graal3D server; Offline walks the default level.

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

The Hardware options and Player look windows (their settings come from
`graal3dconfig.txt` for now), full screen, arm and leg swing while walking,
and saving the nickname and password between runs.

## Checks behind this release

The test suite (107 checks) runs with range and overflow checks and the
heap tracer and must end with no unfreed memory; it includes 2000 damaged
level files read without a crash. CI walks the stand-in level offline on
Linux and Windows, and logs two of these clients into the Graal3D
reference server: both log in, save the level as sent, see each other and
swap a chat line over UDP.
