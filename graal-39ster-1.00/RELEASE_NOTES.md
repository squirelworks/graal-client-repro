# 39ster's Graal client 1.00

A behavioural port of 39ster's Graal client 1.00, the 2014 offline fan
remake, in Delphi (Object Pascal). This first version is a viewer: it draws
a level of the player's own 39ster install in a 640 x 480 window and moves
the view with the arrow keys. Walking, collision, animation, signs and
links come next.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, Stéphane Portha ("unixmad"), or 39ster.

These zips hold none of the original's engine, script, graphics or levels.
Put the program in the folder of a 39ster install you own, or point it at
one with `--data DIR`, or keep the install's files in
`graal-assets/39ster/` next to it.

## What's new in v0.0.5

- [x] **New client.** 39ster's client joins the set as its own profile
  (#176): level13.nw at (512, 512), the 640 x 480 view and the camera
  clamped to the level.
- [x] **The player's own files.** Levels, the tile sheet and the category
  table are read from the install at run time.

## Not yet

- [ ] The player character, walking and collision, animation, pause, grab
  and pull, signs and links (see the README's "Not yet").

## Downloads

| Zip | Runs on | Window |
|---|---|---|
| `…-linux.zip` | Linux x86-64 | X11 |
| `…-windows.zip` | Windows, 32-bit | GDI |

Each zip has `Graal39ster` (the program) and the build's README.

## Running it

```
Graal39ster                                   # in the install's folder
Graal39ster --data DIR                        # an install elsewhere
Graal39ster --data DIR --frame out.bmp        # one frame, no window
```
