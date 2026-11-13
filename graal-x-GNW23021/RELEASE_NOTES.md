# GraalX (GNW23021)

A rebuild of the GraalX client in Delphi (Object Pascal). GraalX is a 2.01
pre-release that kept the `.nw` (GLEVNW01) level code 2.01 dropped; this
rebuild is the 2.01 rebuild with that code turned on and GraalX's own exe
resources. Like the original it is a windowed program: it opens on a start
screen with Training (the offline levels), the server list from the
listserver, and login. This is an early, hit-or-miss first release.

**Login token: tested against the real client.** The original was run in the lab and `GNW23021` was seen in its login on the wire (logged by a lab game server); this rebuild sends the same token.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

These zips hold no original Graal code, graphics, sounds or levels. The
program carries small original default graphics and a starter level of its
own, so it runs as it is. Put it next to a 2.01 install you own (or
keep a `graal-assets/` folder next to it, or point it at one with
`--data DIR`) and the install's tiles, ganis, heads, bodies and levels take
their place.

## What's new in v0.0.5

- [x] **Esc asks before quitting.** In offline play, Esc opens the real client's question, "Warning" / "Do you really want to quit Graal?" with OK and Cancel (worded from the language file's `MainWindow-Error0` and `Reconnect-Error5`); OK ends the program and Cancel goes back to the game. Before, Esc dropped straight back to the start window. On Windows it is a real message box. Online, Esc still leaves the game; the real "Continue / End" scroll is not built yet (#302, lab on Windows XP, 2026-11-13).
- [x] **Server list as the language file words it.** The list window's labels and Connect button take their `ServerList-*` captions from the install's language file (the form's own text when a key is missing), no row is picked until the player picks one, the Account and Password boxes keep the form's `guest` (the password masked) when nothing was saved, and the read-only Name, Language, Version and Homepage boxes show the start of their text instead of clipping it on the left (#302, from the 2026-11-12 polishing run).

## What's new in v0.0.4.2

- [x] **New client.** GraalX joins the set as its own folder, on the 2.01
  baseline (#175).
- [x] **`.nw` levels.** GLEVNW01 levels on disk load, as in GraalX; the
  2.01 rebuild still refuses them.
- [x] **Its own resources.** Every RCDATA resource of `GraalX.exe` is
  compiled in (`src/ResGraalX.pas`), with its own icon. Its main form is the
  one 2.02 also has, not 2.01's.
- [x] **Saving `.nw` levels.** A `.nw` level opened in the editor and saved
  unchanged keeps every byte, as GraalX's own did in the one run the
  research made; edited tiles, NPCs and signs save and load back.
- [x] **As 2.01 now does:** the minimap only on a level of its grid, and F1
  opens the Help window from the build's own form.
- [x] **F1 window captions.** The Help window takes its title and button captions from your install's language file (`Options=`, `Options-<button>=`), as the original does, so an install whose file says "Options" and "More options" shows those. The buttons are drawn letter-spaced with the hotkey letter in red, and the current level field shows the level's full path, selected.

## Not yet

- [ ] The `.nw` open-dialog filter, numeric display and condition context,
  whether edited `.nw` levels are written as GraalX writes them, and a side-by-side run against the real
  GraalX (see the README's "Not yet").
- [ ] Text in the dialogs uses Liberation Sans for the forms' MS Sans
  Serif, so glyphs differ by a pixel here and there.
- [ ] The Options window, the Get an account and homepage GO buttons, and
  the list's right-click menu do nothing yet.
- [ ] Full screen stretches the 640 x 480 picture; whether 2.0x showed
  more of the level at 800 x 600 and 1024 x 768 is not checked yet.
- [ ] The "Getting server list ..." box is drawn inside the list window,
  not as a window of its own.
- [ ] The password is not saved (the real client keeps it in the registry).
- [ ] The Windows version block still names this project, not the
  original's company and product strings.

## Downloads

| Zip | Runs on | Window |
|---|---|---|
| `…-linux.zip` | Linux x86-64 | X11 |
| `…-windows.zip` | Windows, 32-bit (as 2.01 itself was) | GDI |

Each zip has `GraalX` (the client) and the build's README. The test
programs are built and run on every release but no longer shipped.

On Windows the first start may show **"Windows protected your PC"**. That
is SmartScreen meeting an unsigned program it has not seen before, not a
virus warning. Either click **More info**, then **Run anyway** (once), or
unblock the zip before you extract it: right-click it, **Properties**,
tick **Unblock**, **OK**. Then nothing in the folder is asked about again.
See [Windows says "Windows protected your PC"](https://github.com/squirelworks/graal-client-repro#windows-says-windows-protected-your-pc).

## What works

- The 2.01 login: gen-3 cipher, zlib framing, token `GNW23021`.
- The server list from `listserver.graal.in` (port 14923; another can be
  named in `listserver.txt`), then account and password.
- Levels (`.graal`, `.zelda`) and the big map, drawn from the install's
  tiles and ganis; walking, collision, level links and warps.
- NPCs and the GS1 script engine, items, combat, signs, weapons, baddies,
  sound, the map and the level editor.
- A headless mode for stress runs.

## Running it

```
GraalX                                                   # start screen
GRAAL_PW=... GraalX --server HOST:PORT --account NAME
GraalX --level some.graal                                # offline
```

Arrow keys walk, Esc leaves the game. `GraalX --help` lists every flag.

## Not yet

Chat bubbles, the Options page, UDP peer traffic and parts of
GS1 are not done.
