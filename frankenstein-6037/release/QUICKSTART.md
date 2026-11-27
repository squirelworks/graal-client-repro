# Frankenstein 6.037: quick start

An experimental, unofficial client: a Graal 6.037 program with the 5.12
Graal3D world folded in. It is a fan rebuild, hit or miss, and it ships no
game data. It is not affiliated with GraalOnline or Cyberjoueurs.

## What is in this zip

| File | What it is |
|---|---|
| `frankenstein-6037` (`.exe` on Windows) | the client |
| `play.command` (macOS, Linux) / `play.bat` (Windows) | a launcher that asks for the server, account and password |
| `QUICKSTART.md` | this page |
| `README.md`, `RELEASE_NOTES.md` | the developer notes and the change list |
| `MANIFEST.txt`, `VERSION` | what the build is |

The macOS program is universal: it runs on Apple Silicon (M1 and later)
and on Intel Macs, macOS 11 or newer.

## macOS: opening an unsigned program

The program is not signed or notarised, so macOS refuses it the first time.
Either way below works; you only do it once.

- **Terminal (simplest):** open Terminal, type `cd ` (with a space), drag
  the unzipped folder onto the window, press Return, then run
  `xattr -dr com.apple.quarantine .` and `./play.command`.
- **Finder:** right-click (or Control-click) `play.command`, choose
  **Open**, then **Open** again in the warning. If macOS still says it
  cannot be opened, go to **System Settings > Privacy & Security**, scroll
  down, and click **Open Anyway** beside the blocked item, then try again.
  Do the same for `frankenstein-6037` if it is named.

`play.command` clears the quarantine mark on its own folder each time it
starts, so after the first run a double-click is enough.

## Connecting to a server

Run the launcher and answer its three questions:

```
Server (host:port): your.server.example:14900
Account: yourname
Password:
```

Or start the client directly:

```
FRANK_PASSWORD=secret ./frankenstein-6037 --connect HOST:PORT --account NAME \
  --password-env FRANK_PASSWORD --assets ./data --download-files
```

- `HOST:PORT` is the game server (a Seihai gserver, for instance). The
  program logs straight into it; there is no server list screen yet.
- A 3D server is one whose name starts with `3 `. Add
  `--server-name "3 Lab"` (or set `FRANK_SERVER_NAME="3 Lab"` for the
  launcher), or let the server's own warp send you there. The 3D link is
  UDP on the server's port + 1, so that port must be reachable as well.
- `--assets DIR` is where game files are read from and downloaded to. Point
  it at an existing Graal install folder if you have one (set
  `FRANK_ASSETS` for the launcher); otherwise the launcher uses `data/`
  beside it and `--download-files` asks the server for what is missing.

## Useful options

| Option | What it does |
|---|---|
| `--renderer software` | draw the 3D view without OpenGL (use this if the window is black or the program stops on start). `opengl` forces OpenGL; `auto` (default) tries OpenGL and falls back |
| `--max-fps N` | cap the 3D view's frame rate (60 by default, 0 for no cap) |
| `--no-fps` | hide the frame-rate counter |
| `--no-3d-view` | keep the plain 2D (6.x) frame |
| `--no-seihai3d` | do not send the Seihai 3D extension hello, for a server that refuses it |
| `--offline LEVEL.nw --assets DIR` | walk a level from your own files with no server |
| `--bench all --seconds 5` | measure frame rates on the built-in test worlds, no server needed |

With the launcher, put options after it: `./play.command --renderer software`.

## What works now

- Logging in to a 6.x-style server with the 6.03r7 login, levels, players,
  the 6.x HUD and GS2 weapon scripts.
- Entering a `3 ` server: the 5.12 UDP link to login step 6, your own 3D
  object (arrow keys move it), other players' ghosts and server moves.
- The 3D world drawn while the server names a camera: sky, terrain, water,
  `.3ds`, `.dts` and `.dif` shapes, name tags, by OpenGL or the software
  renderer, with the 2D frame as a small inset bottom left.
- Shapes and textures the 3D world needs are requested from the server and
  kept under the assets folder.
- Tested in CI on macOS (Apple Silicon), Linux and Windows: it starts,
  logs in through a Login server, takes the warp to a `3 ` server and
  brings the UDP link up. It was also run against a real Seihai gserver in
  its `graal3d` mode on 2026-11-26.

## Known gaps

- No start screen or server list: you must give the server on the command
  line or in the launcher.
- No mouse-look and none of the 5.12's own 3D controls; the arrow keys walk
  the 2D player and the 3D object follows.
- No `TerrainChunkEvent` and no `fixedudpport` option yet.
- No Metal renderer; OpenGL 3.2 (which macOS still runs, on Metal) or the
  software renderer is used.
- Until the server names a camera the 3D view is black, as the real 5.12's
  is. A server without a 3D mode just gives you the 2D game.
- Expect crashes and odd drawing. Run it from Terminal so the log is
  visible, and send the last lines of that log with any report.
