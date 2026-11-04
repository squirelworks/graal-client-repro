# Graal Adventure Demo v1.10, Game Boy Color (1999)

The Game Boy Color demo of Graal, rebuilt. Original: `Graal V1.1 Adventure
Demo (PD) [C].gbc` (the same bytes as `graal.gb` in `graalgb.rar`),
262,144 bytes, MD5 `2b2fef91df11f9fbae3e1ece2366fdd3`, a GBDK 2.x C program
for an MBC1 cartridge. It has no network and no version token, so the
folder is named `graalgb-<version>` rather than `graal-<version>-<token>`
(which also keeps it out of the Delphi build and release scripts, which
pick up every `graal-*` folder).

Like the original, it is written in C with GBDK and builds a `.gbc` ROM.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad"). "Graal"
> and related names are trademarks of their respective owners and are used
> here only to identify the software being reimplemented.

This folder holds no code, graphics, rooms, palettes or text of the
original. The engine is written from notes on what the demo does and how
its data is laid out, not from its code. The ROM it builds carries stand-in
art and rooms made for this project; `tools/import_assets.py` swaps in the
original's graphics, rooms and texts from a copy of the demo that you own.

## Sources

| Area | Notes |
|---|---|
| Rooms, links, texts, NPC records, characters, controls | graal_analysis `client-internals/gameboy-demo.md` |
| What the demo does in play (speeds, sword, lifting, A items, the captive, Start) | the same note, "Seen in an emulator" |
| Where the data sits in the ROM (for the importer) | the shared notes on the ROM's layout (`graal-decompile/gameboy-demo/`, data regions only) |
| The start point, the link and wall tests, corner sliding, the text box and menu layout | measured on the running demo in an emulator (positions in WRAM, the window map and OAM), written down in the code where each is used |

## Layout

| Path | What |
|---|---|
| `build.sh` | builds the ROM: `build/graalgb-1.10/GraalGB.gbc` |
| `src/pak.c`, `src/pak.h` | reads the asset pack (banks 8 to 15); the only code that maps other banks |
| `src/main.c` | start-up and the frame loop: double speed, logic every second frame (30 Hz) |
| `src/room.c` | rooms: loading, walls, live map, animated tiles, links, signs |
| `src/ent.c` | the player and NPCs: walking, sword, knock-back, wander, patrol, chase, the captive's event |
| `src/obj.c` | lifting, carrying, throwing, the bomb and the boomerang |
| `src/draw.c` | the camera and sprites |
| `src/ui.c` | the text box and the Select menu |
| `src/sfx.c` | sound effects, and Start |
| `tools/gpak.py` | the asset pack format and the step that puts a pack into a ROM |
| `tools/make_builtin.py` | draws the stand-in art and rooms and writes their pack |
| `tools/import_assets.py` | writes a pack from your copy of the demo and makes `GraalGB-original.gbc` |
| `tests/smoke.py` | plays the ROM in an emulator (PyBoy) and checks the main actions |

The engine holds no assets. Banks 0 and 1 hold the code; banks 8 to 15 hold
an asset pack (`tools/gpak.py`): tile sets, font, walk bits, palettes,
animated tiles, sprites, the 31 characters (name, palettes, head, sword
colour, A item), heads, liftable objects, the start, and the seven rooms in
the demo's own record layout (map and attributes, links, texts, NPCs).

## Build, test, run

```
# GBDK-2020 4.3.0 from https://github.com/gbdk-2020/gbdk-2020/releases
export GBDK_HOME=/path/to/gbdk
graalgb-1.10/build.sh                       # build/graalgb-1.10/GraalGB.gbc
pip install pyboy
python3 -I graalgb-1.10/tests/smoke.py build/graalgb-1.10
```

On Windows, run the same from Git Bash with `GBDK_HOME` pointing at the
unpacked `gbdk-win64.zip` and `PYTHON=python`.

Run `GraalGB.gbc` in any Game Boy Color emulator, or on a flash cartridge.

### With the original graphics

Put your copy of the demo next to `GraalGB.gbc` (any name ending in `.gb`
or `.gbc`; it is found by its MD5), or in `graal-assets/gb-1.10/` or
`graal-assets/common/` inside that folder, and run

```
python3 -I import_assets.py            # in the release zip
python3 -I graalgb-1.10/tools/import_assets.py --rom build/graalgb-1.10/GraalGB.gbc   # in the repo
```

It writes `GraalGB-original.gbc` next to `GraalGB.gbc`. `--data DIR` looks
in another folder first. Nothing above the ROM's folder is read. The only
file it needs is the demo itself.

## What works

- **No title screen**, as in the demo: the game opens in room 0 with the
  player in the middle, facing down. The CGB runs in double speed and the
  logic runs at 30 Hz.
- **Seven rooms** of 32x32 tiles joined by links (a rectangle, a new x and
  y, -1 keeps a coordinate), loaded with the screen off. The camera keeps
  the player in the middle and stops at the edges.
- **Walking** at 4 pixels a logic tick, with the demo's wall test (the
  16x16 body, three points on the leading edge), its corner sliding (a
  nudge toward the free corner, 4 half pixels a tick, not tested against
  the rest of the body) and its link test (the centre moved one half pixel
  the way the player faces). On the demo's own rooms, walking traces match
  the demo position for position, apart from the frames a room load takes.
- **Signs** (face up into the post) and **people with something to say**
  (walk into them). The text box is the demo's: nine rows from y 72, three
  lines of 18 on every second row, the font's own frame tiles, capitals
  and punctuation in their own palette. A new press of a direction other
  than the one faced turns the page.
- **The Select menu** over the whole screen: three heads (front view,
  mirrored) over bodies, the middle one's name, Button B and Button A with
  their icons; left and right turn through all 31 characters.
- **B, the sword**, for everyone, in the character's colour (red, blue for
  characters 1 and 17, purple for 6). A hit knocks back and blinks;
  nothing dies and there is no damage.
- **A, the character's item**: lift and throw for character 0 (bushes,
  stones and the post; the lifted tiles stay until the room is loaded
  again; a thrown object always breaks into four pieces), a bomb for
  character 2 (a plus-shaped blast that knocks back), a boomerang for
  character 7. Only those three have an A item.
- **NPCs**: standing, wandering and patrolling inside the box their record
  gives; flag bit 0 turns one to watch the player once lined up, and with
  bit 7 too it chases and swings (the two soldiers in room 3).
- **The captive** (event 1): after its first text it walks two tiles left,
  lifts the bush there, turns, throws it, and opens its second text; the
  player waits meanwhile.
- **Sound effects** on the pulse and noise channels. **Start** does what it
  does in the demo: the music player has no song (the demo reads it from
  cartridge RAM it does not have), so the sound goes off until a reset.

## Not yet

These are for 0.0.2 and later:

- People in the game are drawn with this project's own bodies even with
  the original assets; the demo builds them from its heads and its body
  frames, which the importer does not map yet. Their colours use the
  character's first palette only.
- The object sprites (carried and thrown things, bomb, blast, boomerang)
  and the menu icons are always this project's own.
- Timing details: the frames a room load takes, the slide in 2-unit steps
  every frame, the captive's walking speed, how long each event step
  waits, the carousel's scrolling animation in the menu.
- The rules of NPC movement modes 2 to 4 beyond a left-right patrol, an
  up-down patrol and a wander; the NPC flag bits other than 0 and 7; the
  second walk-bit set.
- The original runs on a monochrome Game Boy too (header flag $80). This
  rebuild sets the same flag but needs a Game Boy Color: on an older model
  it shows a blank screen.
- A side-by-side, action-by-action comparison with the demo (this is the
  0.0.2 check).

## Assets the build opens

For the shared assets zip: one file, the demo ROM, 262,144 bytes, MD5
`2b2fef91df11f9fbae3e1ece2366fdd3`, as `graal-assets/gb-1.10/graal.gbc`.
The importer reads its tile sets, font, walk bits, BG palettes, animated
tiles, heads, character table, liftable-object tables and the seven rooms.
