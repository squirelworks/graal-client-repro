# Graal 2.17.1 (GNW22122)

A rebuild of the classic Graal 2.17.1 client in Delphi (Object Pascal).
Like the original it is a windowed program: it opens on a start screen
with Training (the offline tutorial), the server list from the listserver,
and login. It talks the 2.17.1 wire protocol (the 2.05 cipher and zlib
frames, the 2.17 login with its tamper check, the 2.1 props) and plays
what the 2.05 rev 2 rebuild plays, with the 2.1 to 2.17 additions the
offline tutorial needs.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

These zips hold no original Graal code, graphics, sounds or levels. The
program carries small original default graphics and a starter level of its
own, so it runs as it is. 2.17.1 shipped in the same folder as 2.22: put it
in that install (or point it at one with `--data DIR`, or keep a
`graal-assets/` folder inside the program's folder) and the install's tiles, ganis, heads,
bodies and offline tutorial take their place.

## What's new in v0.0.3

- The Windows program carries its original's own icon (the Graal head, taken from
  the original exe), so Explorer shows it as the original did.
- Stress tested before release: a long soak with several players walking
  between levels, others connecting and dropping again and again, and a
  level with 80 scripted NPCs, with no crash, error or memory growth.

## Downloads

| Zip | Runs on | Window |
|---|---|---|
| `…-linux.zip` | Linux x86-64 | X11 |
| `…-windows.zip` | Windows, 32-bit (as 2.17.1 itself was) | GDI |

Each zip has `Graal217` (the client) and the build's README. The test
programs are built and run on every release but no longer shipped.

On Windows the first start may show **"Windows protected your PC"**. That
is SmartScreen meeting an unsigned program it has not seen before, not a
virus warning. Either click **More info**, then **Run anyway** (once), or
unblock the zip before you extract it: right-click it, **Properties**,
tick **Unblock**, **OK**. Then nothing in the folder is asked about again.
See [Windows says "Windows protected your PC"](https://github.com/squirelworks/graal-delphi#windows-says-windows-protected-your-pc).

## What works

- The start screen: nick name, Training, Start. Start fetches the server
  list from `listserver.graal.in:14923` (the public listserver's port for
  the classic list login 2.17.1 sends), or from the install's
  `arrays2.dat`, or `listserver.txt` next to the program.
- Training: the offline tutorial levels with their tile set (`addtiledef`),
  the tutorial character (`replaceani`, gani attributes `#P1` to `#P30`,
  `ATTACHSPRITE`), and the tutorial's NPCs and scripts.
- Login to a 2.17.1 server: `GNW22122`, the tamper check once after the
  language, the 2.1 props (GANI as text, direction-only sprite), and the
  prop streams stopping where 2.17.1's own parsers stop.
- From the 2.05 rev 2 rebuild: walking and collision, level links, the
  sword, lift and throw, chests, floor items, signs, weapons and the bow,
  bombs, being hurt, dying and respawning, level NPCs running GS1,
  baddies, sound effects, the big map and minimap, and the F4 editor.
- Names under NPC characters and other players.
- A headless mode for stress runs, with a random walker, JSON stats and
  clean shutdown on SIGTERM / Ctrl+C.

## Running it

Start `Graal217` with no arguments for the start screen. From a terminal:

```
GRAAL_PW=... Graal217 --server HOST:PORT --account NAME --data /path/to/graal
Graal217 --level offlinetutorial_b-2.graal --data /path/to/graal   # offline
Graal217 FILE.graal                                                 # the editor
```

Arrow keys or I/J/K/L walk, S swings, A lifts, throws or opens, D uses the
weapon, Q the item list, M the map; Esc leaves the game. Run
`Graal217 --help` for every flag.

## Not yet

Gmaps, the ids 169 to 185, large file downloads, the GS1 commands added
after 2.05 (beyond `addtiledef` and `replaceani`), gani scripts, chat
bubbles, Options, UDP peer traffic, and a side-by-side check against the
real 2.17.1. See the build's README.

## Checks behind this release

The test suites (Test217 with the NPC and baddy tests, TestEditor217,
TestSoundMap217) run with range and overflow checks and the heap tracer,
and must end with no unfreed memory. CI also logs two of these clients
into seihai-gserver, has the second see the first, and walks one through
a level link.
