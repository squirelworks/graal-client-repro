"""Draws the stand-in assets of the Graal Game Boy Color rebuild and writes
them as an asset pack (see gpak.py).

Everything here is new art and new room layouts made for this project: no
tile, pixel, palette, room or text of the original demo. The rooms keep the
demo's shape (seven rooms, the same links between them, the same kinds of
people standing in them) so that the engine can be tried out end to end
without the original ROM. import_assets.py replaces all of it with the
player's own copy.

Usage: python3 -I make_builtin.py TOOLS_DIR FONT5x7_PY OUT.bin
  TOOLS_DIR   this folder (for gpak.py)
  FONT5x7_PY  scripts/builtin/font5x7.py, the repo's own 5x7 font
Standard library only.
"""
import os
import random
import sys

sys.path.insert(0, sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__)))
import gpak  # noqa: E402


# ---------------------------------------------------------------- tiles
def tile2bpp(rows):
    """8 rows of 8 colour indexes (0-3) to 16 bytes."""
    out = bytearray()
    for r in rows:
        lo = hi = 0
        for x, c in enumerate(r):
            if c & 1:
                lo |= 0x80 >> x
            if c & 2:
                hi |= 0x80 >> x
        out += bytes([lo, hi])
    return bytes(out)


def parse(art):
    """ASCII art (rows of '.0123') to a list of lists of colour indexes."""
    rows = [r.strip() for r in art.strip().splitlines()]
    return [[0 if ch in '.0' else int(ch) for ch in r] for r in rows]


def cut(img, tx, ty):
    return [row[tx * 8:tx * 8 + 8] for row in img[ty * 8:ty * 8 + 8]]


def tiles_rowmajor(img):
    """An image to 8x8 tiles, left to right, top to bottom (background)."""
    h, w = len(img) // 8, len(img[0]) // 8
    return [tile2bpp(cut(img, x, y)) for y in range(h) for x in range(w)]


def tiles_8x16(img):
    """A 16x16 image to four tiles in 8x16 sprite order: TL, BL, TR, BR."""
    return [tile2bpp(cut(img, 0, 0)), tile2bpp(cut(img, 0, 1)),
            tile2bpp(cut(img, 1, 0)), tile2bpp(cut(img, 1, 1))]


def blank(w, h, c=0):
    return [[c] * w for _ in range(h)]


def disc(img, cx, cy, r, c):
    for y in range(len(img)):
        for x in range(len(img[0])):
            if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                img[y][x] = c


def rect(img, x0, y0, x1, y1, c):
    for y in range(y0, y1):
        for x in range(x0, x1):
            img[y][x] = c


# outdoor tile ids
GRASS, TUFT, FLOWER, WATER, PATH = 0, 1, 2, 3, 4
BUSH, ROCK, POST, STUMP, HOLE = 12, 16, 20, 24, 28
HOUSE = 32          # 6 x 4 tiles, row-major, 32..55
FENCE = 56
TREE = 64           # 4 x 4 tiles, row-major, 64..79
# indoor tile ids
FLOOR, WALL, WALLTOP, RUG, MAT, VOID = 0, 1, 2, 3, 4, 5
TABLE, BED, POT = 8, 12, 16          # 2x2 each, row-major


def outdoor_tiles():
    t = [tile2bpp(blank(8, 8))] * 256
    pal = [0] * 256
    rnd = random.Random(7)

    def grass_tile(seed):
        r = random.Random(seed)
        img = blank(8, 8)
        for _ in range(3):
            img[r.randrange(8)][r.randrange(8)] = 1
        return img

    t[GRASS] = tile2bpp(grass_tile(1))
    tuft = blank(8, 8)
    for x, y in ((1, 5), (2, 4), (3, 5), (4, 3), (5, 5), (6, 4)):
        tuft[y][x] = 2
        tuft[y + 1][x] = 2
    t[TUFT] = tile2bpp(tuft)
    fl = blank(8, 8)
    disc(fl, 3, 3, 2, 3)
    fl[3][3] = 1
    fl[6][3] = fl[7][3] = 2
    t[FLOWER] = tile2bpp(fl)
    pal[FLOWER] = 6
    # water, four frames (the engine cycles them; frame 0 is the tile)
    waves = []
    for f in range(4):
        img = blank(8, 8, 1)
        for y in (1, 5):
            for k in range(3):
                img[y][(k + f * 2 + (y // 4) * 3) % 8] = 3 if k == 1 else 2
        waves.append(tile2bpp(img))
    t[WATER] = waves[0]
    pal[WATER] = 3
    pth = blank(8, 8, 1)
    for _ in range(4):
        pth[rnd.randrange(8)][rnd.randrange(8)] = 2
    t[PATH] = tile2bpp(pth)
    pal[PATH] = 2

    # bush: a round shrub
    bush = blank(16, 16)
    disc(bush, 7.5, 8, 7, 3)
    disc(bush, 7.5, 7.5, 6, 2)
    for cx, cy in ((5, 5), (10, 6), (6, 10), (10, 10)):
        disc(bush, cx, cy, 1.5, 1)
    rock = blank(16, 16)
    disc(rock, 7.5, 8.5, 7, 3)
    disc(rock, 7.5, 8, 6, 2)
    disc(rock, 5.5, 5.5, 2.5, 1)
    post = blank(16, 16)
    rect(post, 2, 2, 14, 10, 3)
    rect(post, 3, 3, 13, 9, 1)
    for y in (4, 6):
        rect(post, 5, y, 11, y + 1, 2)
    rect(post, 6, 10, 10, 16, 3)
    rect(post, 7, 10, 9, 15, 2)
    stump = blank(16, 16)
    disc(stump, 7.5, 9, 5, 3)
    disc(stump, 7.5, 8.5, 4, 2)
    disc(stump, 7.5, 8.5, 1.5, 1)
    hole = blank(16, 16)
    disc(hole, 7.5, 8.5, 5, 3)
    disc(hole, 7.5, 9.5, 4, 2)
    for base, img, p in ((BUSH, bush, 1), (ROCK, rock, 5), (POST, post, 2), (STUMP, stump, 1), (HOLE, hole, 2)):
        for i, tile in enumerate(tiles_rowmajor(img)):
            t[base + i] = tile
            pal[base + i] = p

    # house, 48 x 32: a roof (palette 4) over a wall with a door (palette 5)
    roof = blank(48, 16, 1)
    for y in range(16):
        for x in range(48):
            if y == 0 or x in (0, 47):
                roof[y][x] = 3
            elif (y % 4 == 3) or ((x + (y // 4) * 4) % 8 == 0):
                roof[y][x] = 2
    wall = blank(48, 16, 1)
    rect(wall, 0, 0, 48, 1, 3)
    rect(wall, 0, 0, 1, 16, 3)
    rect(wall, 47, 0, 48, 16, 3)
    for wx in (4, 32):                                  # windows
        rect(wall, wx, 4, wx + 12, 11, 3)
        rect(wall, wx + 1, 5, wx + 11, 10, 2)
    rect(wall, 17, 3, 31, 16, 3)                        # door
    rect(wall, 18, 4, 30, 16, 2)
    for i, tile in enumerate(tiles_rowmajor(roof + wall)):
        t[HOUSE + i] = tile
        pal[HOUSE + i] = 4 if i < 12 else 5
    fence = blank(8, 8)
    rect(fence, 0, 2, 8, 4, 3)
    rect(fence, 0, 5, 8, 7, 3)
    rect(fence, 3, 0, 5, 8, 3)
    rect(fence, 0, 3, 8, 3, 2)
    t[FENCE] = tile2bpp(fence)
    pal[FENCE] = 2

    # tree, 32 x 32: a round crown on a short trunk
    tree = blank(32, 32)
    rect(tree, 13, 20, 19, 31, 3)
    rect(tree, 14, 20, 18, 31, 2)
    disc(tree, 15.5, 12, 13, 3)
    disc(tree, 15.5, 11.5, 12, 2)
    for cx, cy, r in ((10, 8, 4), (20, 7, 3.5), (15, 15, 4), (23, 15, 3)):
        disc(tree, cx, cy, r, 1)
    trunk_rows = set()
    for i, tile in enumerate(tiles_rowmajor(tree)):
        t[TREE + i] = tile
        pal[TREE + i] = 2 if (i // 4 == 3 and i % 4 in (1, 2)) else 1
    del trunk_rows
    anim = [(WATER, waves)]
    walk = {GRASS, TUFT, FLOWER, PATH} | set(range(STUMP, STUMP + 4)) | set(range(HOLE, HOLE + 4))
    walk |= {HOUSE + 20, HOUSE + 21}           # the door's bottom row
    return t, pal, anim, walk


def indoor_tiles():
    t = [tile2bpp(blank(8, 8))] * 256
    pal = [0] * 256
    fl = blank(8, 8, 1)
    rect(fl, 0, 3, 8, 4, 2)
    rect(fl, 0, 7, 8, 8, 2)
    fl[1][5] = fl[5][1] = 2
    t[FLOOR] = tile2bpp(fl)
    wl = blank(8, 8, 1)
    for y in (2, 5):
        rect(wl, 0, y, 8, y + 1, 2)
    wl[0][3] = wl[1][3] = wl[3][7] = wl[4][7] = 2
    t[WALL] = tile2bpp(wl)
    pal[WALL] = 1
    wt = blank(8, 8, 2)
    rect(wt, 0, 6, 8, 8, 3)
    t[WALLTOP] = tile2bpp(wt)
    pal[WALLTOP] = 1
    rug = blank(8, 8, 1)
    rect(rug, 0, 0, 8, 1, 2)
    rect(rug, 0, 7, 8, 8, 2)
    rug[3][3] = rug[4][4] = 3
    t[RUG] = tile2bpp(rug)
    pal[RUG] = 3
    mat = blank(8, 8, 2)
    rect(mat, 1, 1, 7, 7, 1)
    t[MAT] = tile2bpp(mat)
    pal[MAT] = 3
    t[VOID] = tile2bpp(blank(8, 8, 3))
    pal[VOID] = 1
    table = blank(16, 16, 0)
    rect(table, 1, 2, 15, 12, 3)
    rect(table, 2, 3, 14, 10, 1)
    rect(table, 2, 12, 4, 16, 3)
    rect(table, 12, 12, 14, 16, 3)
    bed = blank(16, 16, 0)
    rect(bed, 1, 0, 15, 16, 3)
    rect(bed, 2, 1, 14, 5, 1)
    rect(bed, 2, 6, 14, 15, 2)
    pot = blank(16, 16, 0)
    disc(pot, 7.5, 9, 6, 3)
    disc(pot, 7.5, 8.5, 5, 1)
    rect(pot, 5, 2, 11, 5, 3)
    rect(pot, 6, 3, 10, 4, 2)
    for base, img, p in ((TABLE, table, 2), (BED, bed, 3), (POT, pot, 2)):
        for i, tile in enumerate(tiles_rowmajor(img)):
            t[base + i] = tile
            pal[base + i] = p
    walk = {FLOOR, RUG, MAT}
    return t, pal, [], walk


# ---------------------------------------------------------------- palettes
GRASSC = (136, 208, 96)


def outdoor_palettes():
    return [
        [GRASSC, (104, 184, 72), (64, 136, 48), (24, 56, 24)],          # 0 grass
        [GRASSC, (120, 200, 88), (48, 120, 48), (16, 48, 24)],          # 1 trees, bushes
        [GRASSC, (224, 192, 128), (160, 104, 56), (64, 40, 16)],        # 2 path, wood
        [(72, 136, 224), (72, 136, 224), (40, 88, 184), (224, 240, 255)],  # 3 water
        [GRASSC, (208, 88, 56), (136, 48, 32), (48, 16, 8)],            # 4 roof
        [GRASSC, (208, 204, 192), (128, 124, 116), (40, 40, 40)],       # 5 stone, walls
        [GRASSC, (248, 248, 232), (64, 136, 48), (216, 40, 40)],        # 6 flowers; red letters
        TEXT_PAL,                                                       # 7 text box
    ]


TEXT_PAL = [GRASSC, (248, 248, 232), (200, 168, 72), (24, 24, 24)]   # box white, gold frame, ink
CAPS_PAL_COLOURS = [GRASSC, (248, 248, 232), (64, 136, 48), (216, 40, 40)]


def indoor_palettes():
    return [
        [(200, 160, 104), (200, 160, 104), (152, 112, 64), (64, 40, 24)],   # 0 floor
        [(232, 224, 200), (216, 200, 168), (152, 136, 104), (40, 32, 24)],  # 1 walls
        [(200, 160, 104), (176, 112, 56), (112, 64, 32), (48, 24, 8)],      # 2 wood
        [(200, 160, 104), (192, 72, 72), (120, 32, 40), (48, 16, 16)],      # 3 cloth
        [(200, 160, 104)] * 4, [(200, 160, 104)] * 4, CAPS_PAL_COLOURS,
        TEXT_PAL,
    ]


# ---------------------------------------------------------------- font and window
FONT_TILES = 82
CAPS_PAL = 6          # the BG palette capitals and punctuation are drawn with


def font_tiles(font_py):
    """82 tiles for VRAM bank 1: glyphs at code - $20 (background colour 1,
    ink colour 3), then the window's arrows ($4D right, $4E left) and frame
    ($4F corner, $50 side, $51 top), drawn for the top-left and flipped."""
    g = {}
    with open(font_py) as f:
        exec(compile(f.read(), font_py, 'exec'), g)
    glyphs = g['G']
    tiles = [tile2bpp(blank(8, 8, 1))] * FONT_TILES
    for code, ch in gpak.code_chars().items():
        rows = glyphs.get(ch, glyphs['?'])
        img = blank(8, 8, 1)
        for y, r in enumerate(rows):
            for x, c in enumerate(r):
                if c == '#':
                    img[y][x + 1] = 3
        tiles[code - 0x20] = tile2bpp(img)
    right = parse("""
        11111111
        11311111
        11331111
        11333111
        11333311
        11333111
        11331111
        11311111""")
    tiles[0x4D] = tile2bpp(right)
    tiles[0x4E] = tile2bpp([list(reversed(r)) for r in right])
    corner = parse("""
        00000000
        02222222
        02333333
        02311111
        02311111
        02311111
        02311111
        02311111""")
    side = parse("""
        02311111
        02311111
        02311111
        02311111
        02311111
        02311111
        02311111
        02311111""")
    top = parse("""
        00000000
        22222222
        33333333
        11111111
        11111111
        11111111
        11111111
        11111111""")
    tiles[0x4F] = tile2bpp(corner)
    tiles[0x50] = tile2bpp(side)
    tiles[0x51] = tile2bpp(top)
    return tiles


def icons():
    """The menu's B and A icons, 16x16 sprites: sword, lift, bomb, boomerang."""
    sword = blank(16, 16)
    for i in range(10):
        sword[2 + i][12 - i] = 3
        sword[2 + i][13 - i] = 1
    rect(sword, 3, 10, 7, 11, 2)
    rect(sword, 5, 8, 6, 13, 2)
    sword[13][2] = sword[12][3] = 3
    bushi = blank(16, 16)
    disc(bushi, 7.5, 8, 6, 3)
    disc(bushi, 7.5, 7.5, 5, 2)
    disc(bushi, 5, 5.5, 1.5, 1)
    bomb = blank(16, 16)
    disc(bomb, 7, 9, 5.5, 3)
    disc(bomb, 5.5, 7.5, 1.5, 1)
    rect(bomb, 9, 2, 10, 5, 2)
    boom = blank(16, 16)
    for i in range(9):
        boom[3 + i][3] = boom[3][3 + i] = 3
        boom[4 + i][4] = boom[4][4 + i] = 2
    out = []
    for img in (sword, bushi, bomb, boom):
        out += tiles_8x16(img)
    return out


# ---------------------------------------------------------------- sprites
# Bodies: 16x16, colour 1 skin, 2 clothes, 3 outline.
HEAD_FRONT = """
    .....3333333....
    ....322222223...
    ...32222222223..
    ...32111111123..
    ...31131113113..
    ...31111111113..
    ....311121113...
    .....3311133...."""
HEAD_BACK = """
    .....3333333....
    ....322222223...
    ...32222222223..
    ...32222222223..
    ...32222222223..
    ...32222222223..
    ....322222223...
    .....3333333...."""
HEAD_SIDE = """
    .....3333333....
    ....322222223...
    ...32222222223..
    ...32222211113..
    ...32222111313..
    ...32222111113..
    ....322211113...
    .....3333333...."""
BODY_FRONT = ["""
    ....33222223....
    ...3122222213...
    ...3132222313...
    ....32222223....
    ....32233223....
    ....3223.323....
    ....333..333....
    ................""", """
    ....33222223....
    ...3122222213...
    ...3132222313...
    ....32222223....
    ....32233223....
    ....3223..33....
    ....333.........
    ................"""]
BODY_SIDE = ["""
    .....3222223....
    .....3222223....
    .....3211123....
    .....3222223....
    .....3223223....
    .....323.323....
    .....33..33.....
    ................""", """
    .....3222223....
    .....3222223....
    .....3221123....
    .....3222223....
    ....32233.223...
    ....323....323..
    ....33......33..
    ................"""]
BODY_UP = ["""
    ....32222223....
    ...3122222213...
    ...3132222313...
    ....32222223....
    ....32233223....
    ....3223.323....
    ....333..333....
    ................""", """
    ....32222223....
    ...3122222213...
    ...3132222313...
    ....32222223....
    ....32233223....
    ....33...323....
    .........333....
    ................"""]
BODY_ARMS_UP = ["""
    ..31.322223.13..
    ..313222222313..
    ...3322222233...
    ....32222223....
    ....32233223....
    ....3223.323....
    ....333..333....
    ................""", """
    ..31.322223.13..
    ..313222222313..
    ...3322222233...
    ....32222223....
    ....32233223....
    ....3223..33....
    ....333.........
    ................"""]


def body(head, legs, hands_up=False):
    img = parse(head) + parse(legs)
    if hands_up:
        # arms raised beside the head
        for y in range(2, 8):
            img[y][2] = 3
            img[y][13] = 3
            img[y][3] = 1 if y < 4 else img[y][3]
    return img


def sprite_sheet():
    """Sprite tiles for VRAM ids 128 up; returns (tiles, index of each part)."""
    frames = {}
    frames['down0'] = body(HEAD_FRONT, BODY_FRONT[0])
    frames['down1'] = body(HEAD_FRONT, BODY_FRONT[1])
    frames['up0'] = body(HEAD_BACK, BODY_UP[0])
    frames['up1'] = body(HEAD_BACK, BODY_UP[1])
    frames['right0'] = body(HEAD_SIDE, BODY_SIDE[0])
    frames['right1'] = body(HEAD_SIDE, BODY_SIDE[1])
    frames['carry0'] = body(HEAD_FRONT, BODY_ARMS_UP[0], True)
    frames['carry1'] = body(HEAD_FRONT, BODY_ARMS_UP[1], True)
    order = ['down0', 'down1', 'up0', 'up1', 'right0', 'right1', 'carry0', 'carry1']
    tiles = []
    for name in order:
        tiles += tiles_8x16(frames[name])
    # sword: vertical blade (8x16), horizontal blade (16x16 as two halves), diagonal (16x16)
    sv = blank(8, 16)
    for y in range(1, 11):
        sv[y][3] = 3
        sv[y][4] = 1
    sv[0][3] = 3
    rect(sv, 1, 11, 7, 12, 2)
    rect(sv, 3, 12, 5, 16, 2)
    tiles += [tile2bpp(sv[:8]), tile2bpp(sv[8:])]              # 32: sword up (tip at top)
    sh = blank(16, 16)
    for x in range(5, 15):
        sh[7][x] = 3
        sh[8][x] = 1
    sh[7][15] = 3
    rect(sh, 4, 5, 5, 11, 2)
    rect(sh, 0, 7, 4, 9, 2)
    tiles += tiles_8x16(sh)                                    # 34: sword right (tip at right)
    sd = blank(16, 16)
    for i in range(10):
        sd[12 - i][3 + i] = 3
        sd[12 - i][4 + i] = 1
    rect(sd, 2, 10, 6, 11, 2)
    rect(sd, 3, 9, 4, 13, 2)
    sd[14][1] = sd[13][2] = 2
    tiles += tiles_8x16(sd)                                    # 38: sword up-right
    # objects, palette 7 (colour 1 yellow, 2 green, 3 dark) unless noted
    bush = blank(16, 16)
    disc(bush, 7.5, 8, 7, 3)
    disc(bush, 7.5, 7.5, 6, 2)
    for cx, cy in ((5, 5), (10, 6), (6, 10)):
        disc(bush, cx, cy, 1.5, 1)
    tiles += tiles_8x16(bush)                                  # 42
    rock = blank(16, 16)
    disc(rock, 7.5, 8.5, 7, 3)
    disc(rock, 7.5, 8, 6, 1)
    disc(rock, 5.5, 5.5, 2, 2)
    tiles += tiles_8x16(rock)                                  # 46
    post = blank(16, 16)
    rect(post, 2, 2, 14, 10, 3)
    rect(post, 3, 3, 13, 9, 1)
    rect(post, 6, 10, 10, 16, 3)
    tiles += tiles_8x16(post)                                  # 50
    leaf = blank(8, 16)
    leaf[2][2] = leaf[2][3] = leaf[3][1] = leaf[3][4] = 3
    leaf[3][2] = leaf[3][3] = 2
    leaf[4][2] = leaf[4][3] = 3
    tiles += [tile2bpp(leaf[:8]), tile2bpp(leaf[8:])]          # 54
    bomb = blank(16, 16)
    disc(bomb, 7.5, 9, 6, 3)
    disc(bomb, 5.5, 7, 1.5, 1)
    rect(bomb, 7, 1, 9, 3, 1)
    tiles += tiles_8x16(bomb)                                  # 56
    flash = blank(16, 16)
    disc(flash, 7.5, 9, 6, 3)
    disc(flash, 7.5, 9, 4, 1)
    tiles += tiles_8x16(flash)                                 # 60
    blast = blank(16, 16)
    disc(blast, 7.5, 7.5, 7.5, 3)
    disc(blast, 7.5, 7.5, 6, 1)
    disc(blast, 7.5, 7.5, 3, 2)
    tiles += tiles_8x16(blast)                                 # 64
    boom = blank(8, 16)
    for i in range(6):
        boom[1 + i][1] = 3
        boom[1][1 + i] = 3
        boom[2 + i if i < 5 else 6][2] = 1
    tiles += [tile2bpp(boom[:8]), tile2bpp(boom[8:])]          # 68
    boom2 = [list(reversed(r)) for r in boom[:8]] + boom[8:]
    tiles += [tile2bpp(boom2[:8]), tile2bpp(boom2[8:])]        # 70
    tiles += icons()                                           # 72: menu icons
    menu_body = blank(16, 16)
    for y, r in enumerate(parse(BODY_FRONT[0])):
        menu_body[y] = r
    tiles += tiles_8x16(menu_body)                             # 88: a body under a menu head
    return tiles


HEAD_STYLES = 6


def head_sets():
    """HEAD_STYLES heads of 8 tiles each, in the pack's head layout: the left
    half of the front view (8x16, drawn mirrored for the right half), the
    left half of the back view, then a 16x16 side view (8x16 order)."""
    out = []
    for style in range(HEAD_STYLES):
        def face(view):
            img = blank(16, 16)
            disc(img, 7.5, 9.5, 6.5, 3)
            disc(img, 7.5, 9.5, 5.5, 1)
            if style == 0:
                rect(img, 2, 3, 14, 8, 2)
            elif style == 1:
                rect(img, 1, 4, 15, 7, 2)
                rect(img, 4, 1, 12, 4, 2)
            elif style == 2:
                rect(img, 2, 3, 14, 10, 2)
                rect(img, 4, 8, 12, 10, 1)
            elif style == 3:
                disc(img, 7.5, 5, 5, 2)
            elif style == 4:
                for x in (2, 5, 9, 12):
                    rect(img, x, 2, x + 2, 7, 2)
            else:
                rect(img, 3, 4, 13, 7, 2)
                rect(img, 1, 7, 4, 15, 2)
                rect(img, 12, 7, 15, 15, 2)
            if view == 'back':
                disc(img, 7.5, 9.5, 5.5, 2)
            elif view == 'front':
                for ex in (5, 10):
                    img[10][ex] = img[11][ex] = 3
                img[14][7] = img[14][8] = 3
            else:
                rect(img, 1, 4, 8, 14, 2)
                img[10][11] = img[11][11] = 3
            return img
        front, back, side = face('front'), face('back'), face('side')
        tiles = [tile2bpp(cut(front, 0, 0)), tile2bpp(cut(front, 0, 1)),
                 tile2bpp(cut(back, 0, 0)), tile2bpp(cut(back, 0, 1))] + tiles_8x16(side)
        out.append(b''.join(tiles))
    return out


# ---------------------------------------------------------------- characters
# Stand-in names: this project's own, one per character slot.
NAMES = ['Wren', 'Guard', 'Shade', 'Luna', 'Storm', 'Vale', 'Mira', 'Rook',
         'Zane', 'Brute', 'Kite', 'Tobin', 'Bram', 'Pell', 'Iris', 'Drake',
         'Elder', 'Gold Guard', 'Gold Storm', 'Gold Zane', 'Gold Brute',
         'Gold Tobin', 'Gold Ash', 'Red Brute', 'Green Guard', 'Blue Drake',
         'Ember', 'Ash', 'Rogue', 'Red Storm', 'Sea Iris']
# Which A item each slot has, and its sword colour (0 red, 1 blue, 2
# purple). These follow what the demo does with each slot, seen in an
# emulator (graal_analysis client-internals/gameboy-demo.md).
A_ITEM = {0: gpak.A_LIFT, 2: gpak.A_BOMB, 7: gpak.A_BOOMERANG}
SWORD_COLOUR = {1: 1, 17: 1, 6: 2}


def char_palette(k):
    r = random.Random(100 + k)
    skin = (248, 200, 152) if k % 3 else (232, 176, 120)
    cloth = (r.randrange(40, 240), r.randrange(40, 240), r.randrange(40, 240))
    if 'Gold' in NAMES[k]:
        cloth = (232, 184, 48)
    elif 'Red' in NAMES[k]:
        cloth = (216, 48, 48)
    elif 'Green' in NAMES[k]:
        cloth = (64, 168, 64)
    elif 'Blue' in NAMES[k] or 'Sea' in NAMES[k]:
        cloth = (56, 96, 216)
    pal = [(0, 0, 0), skin, cloth, (24, 24, 32)]
    return gpak.palette(pal) * 3


def chars_blob():
    out = bytearray([gpak.NUM_CHARS])
    for k in range(gpak.NUM_CHARS):
        name = gpak.encode_text(NAMES[k])[:gpak.NAME_LEN]
        rec = bytearray(name + bytes(gpak.NAME_LEN - len(name)))
        rec += char_palette(k)
        rec += bytes([k % HEAD_STYLES, SWORD_COLOUR.get(k, 0), A_ITEM.get(k, gpak.A_NONE), 0, 0, 0])
        assert len(rec) == gpak.CHAR_REC
        out += rec
    return bytes(out)


SWORD_PALS = [
    [(0, 0, 0), (248, 248, 248), (216, 48, 48), (40, 24, 24)],
    [(0, 0, 0), (248, 248, 248), (56, 104, 224), (24, 24, 56)],
    [(0, 0, 0), (248, 248, 248), (168, 72, 200), (40, 24, 56)],
]
OBJ_PALS = [
    [(0, 0, 0), (248, 216, 96), (96, 176, 72), (24, 40, 24)],      # 5: bushes, leaves
    [(0, 0, 0), (208, 204, 192), (248, 200, 64), (32, 32, 32)],    # 7: rocks, bombs, blast
]


# ---------------------------------------------------------------- rooms
class Room:
    def __init__(self, tileset, fill):
        self.tileset = tileset
        self.t = [fill] * 1024
        self.links = []
        self.texts = []
        self.npcs = []

    def put(self, x, y, tid):
        if 0 <= x < 32 and 0 <= y < 32:
            self.t[y * 32 + x] = tid

    def block(self, x, y, base, w=2, h=2):
        for j in range(h):
            for i in range(w):
                self.put(x + i, y + j, base + j * w + i)

    def tree(self, x, y):
        self.block(x, y, TREE, 4, 4)

    def npc(self, x, y, d, ctype, text=-1, mode=0, bounds=(0, 33, 1, 34), flags=0x0380, event=0):
        self.npcs.append(bytes([x, y, d, ctype, 3, 1, text & 255, mode]) + bytes(bounds) +
                         bytes([flags & 255, flags >> 8, event & 255, event >> 8]))

    def blob(self, palset, palmap):
        attrs = bytes((palmap[t] & 7) | (0x08 if t >= 128 else 0) for t in self.t)
        return gpak.room_blob(self.tileset, palset, self.t, attrs, self.links, self.texts, self.npcs)


def border(room, gaps):
    """A ring of trees two blocks deep, open where gaps say: 'n', 's', 'w', 'e'
    open tiles 8 to 23 of that side."""
    for i in range(0, 32, 4):
        mid = 8 <= i < 24
        if not (mid and 'n' in gaps):
            room.tree(i, 0)
        if not (mid and 's' in gaps):
            room.tree(i, 28)
        if not (mid and 'w' in gaps) and 4 <= i < 28:
            room.tree(0, i)
        if not (mid and 'e' in gaps) and 4 <= i < 28:
            room.tree(28, i)


def sprinkle(room, seed, n=24):
    r = random.Random(seed)
    for _ in range(n):
        x, y = r.randrange(4, 28), r.randrange(4, 28)
        if room.t[y * 32 + x] == GRASS:
            room.put(x, y, r.choice((TUFT, TUFT, FLOWER)))


def wrap18(text):
    """Pads text so that words break at the text box's 18-character lines."""
    lines, cur = [], ''
    for word in text.split():
        if cur and len(cur) + 1 + len(word) > 18:
            lines.append(cur.ljust(18))
            cur = word
        else:
            cur = word if not cur else cur + ' ' + word
    lines.append(cur)
    return ''.join(lines)


def make_rooms():
    def T(text):
        return gpak.encode_text(wrap18(text))
    rooms = []
    # 0: the start. Exits east (to 2) and north (to 3).
    r = Room(0, GRASS)
    border(r, 'ne')
    r.tree(20, 6)
    r.tree(8, 22)
    for x, y in ((6, 6), (6, 9), (8, 12), (5, 15), (7, 18)):
        r.block(x, y, BUSH)
    r.block(16, 11, POST)
    r.texts.append((16, 11, T('Welcome! This is a fan rebuild of a Game Boy Color demo. Have fun exploring!')))
    sprinkle(r, 10)
    r.links += [(31, 8, 1, 16, 1, -1, 2), (8, 0, 16, 1, -1, 31, 3)]
    rooms.append(r)
    # 1: inside the house in room 6. The mat leads out.
    r = Room(1, VOID)
    for y in range(10, 31):
        for x in range(8, 24):
            r.put(x, y, FLOOR)
    for x in range(8, 24):
        r.put(x, 8, WALLTOP)
        r.put(x, 9, WALL)
    for y in range(18, 22):
        for x in range(13, 19):
            r.put(x, y, RUG)
    r.block(9, 11, BED)
    r.block(19, 12, TABLE)
    r.block(21, 26, POT)
    r.put(15, 30, MAT)
    r.put(16, 30, MAT)
    r.links += [(15, 30, 2, 1, 15, 14, 6)]
    rooms.append(r)
    # 2: east of the start. Exits west (to 0) and north (to 5).
    r = Room(0, GRASS)
    border(r, 'wn')
    r.tree(14, 14)
    for y in range(4, 28):
        r.put(22, y, PATH)
        r.put(23, y, PATH)
    for x, y in ((8, 8), (10, 20), (19, 22)):
        r.block(x, y, ROCK)
    r.npc(9, 15, 1, 7)
    sprinkle(r, 20)
    r.links += [(0, 8, 1, 16, 31, -1, 0), (8, 0, 16, 1, -1, 31, 5)]
    rooms.append(r)
    # 3: north of the start; two who chase. Exits north (to 4) and south (to 0).
    r = Room(0, GRASS)
    border(r, 'ns')
    for x in range(4, 28, 2):
        if not 12 <= x < 20:
            r.block(x, 10, BUSH)
    r.npc(16, 5, 3, 1, mode=2, bounds=(12, 21, 1, 34), flags=0x03a1)
    r.npc(16, 18, 2, 4, mode=1, flags=0x0381)
    sprinkle(r, 30)
    r.links += [(8, 0, 16, 1, -1, 31, 4), (8, 31, 16, 1, -1, 1, 0)]
    rooms.append(r)
    # 4: the captive. Exit south (to 3).
    r = Room(0, GRASS)
    border(r, 's')
    r.tree(6, 6)
    r.tree(22, 6)
    r.block(13, 16, BUSH)
    for x, y in ((6, 20), (22, 20), (9, 12)):
        r.block(x, y, BUSH)
    r.npc(17, 17, 2, 0, text=0, flags=0x0001, event=1)
    r.texts.append((0, 0, T('Thank you for getting me out! I will come along. First, watch how to lift a bush: A lifts it, A again throws it!')))
    r.texts.append((0, 0, T('Now press Select and pick me to do the same.')))
    sprinkle(r, 40)
    r.links += [(8, 31, 16, 1, -1, 1, 3)]
    rooms.append(r)
    # 5: north of room 2; three who say hello. Exits south (to 2), north (to 6).
    r = Room(0, GRASS)
    border(r, 'ns')
    for y in range(0, 32):
        r.put(15, y, PATH)
        r.put(16, y, PATH)
    for x in range(8, 13):
        for y in range(8, 12):
            r.put(x, y, WATER)
    r.npc(24, 6, 2, 6, text=0)
    r.npc(22, 14, 1, 3, text=0)
    r.npc(6, 16, 3, 6, text=0)
    r.texts.append((0, 0, T('Hi there!')))
    sprinkle(r, 50)
    r.links += [(8, 31, 16, 1, -1, 1, 2), (8, 0, 16, 1, -1, 31, 6)]
    rooms.append(r)
    # 6: the house. Exits south (to 5) and the door (to 1).
    r = Room(0, GRASS)
    border(r, 's')
    r.block(12, 8, HOUSE, 6, 4)
    for y in range(12, 32):
        r.put(14, y, PATH)
        r.put(15, y, PATH)
    for x in range(20, 25):
        for y in range(16, 20):
            r.put(x, y, WATER)
    for x in range(5, 11):
        r.put(x, 20, FENCE)
    r.block(10, 13, POST)
    r.texts.append((10, 13, T('Your house.')))
    r.npc(22, 24, 1, 5, mode=1)
    r.npc(8, 14, 3, 4, mode=1)
    sprinkle(r, 60)
    r.links += [(8, 31, 16, 1, -1, 1, 5), (14, 11, 2, 1, 16, 27, 1)]
    rooms.append(r)
    return rooms


# ---------------------------------------------------------------- the pack
LIFT_KINDS = [  # (top-left id, top-right id, lifted 2x2, object look)
    (BUSH, BUSH + 1, (STUMP, STUMP + 1, STUMP + 2, STUMP + 3), 0),
    (ROCK, ROCK + 1, (HOLE, HOLE + 1, HOLE + 2, HOLE + 3), 1),
    (POST, POST + 1, (HOLE, HOLE + 1, HOLE + 2, HOLE + 3), 2),
    (0xFF, 0xFF, (0xFF, 0xFF, 0xFF, 0xFF), 0),     # a dropped object (not used here)
]


def lift_blob(kinds):
    out = bytes(k[0] for k in kinds) + bytes(k[1] for k in kinds)
    for k in kinds:
        out += bytes(k[2])
    out += bytes(k[3] for k in kinds)
    return out


def walk_bits(walk):
    b = bytearray(32)
    for t in walk:
        b[t >> 3] |= 1 << (t & 7)
    return bytes(b)


def anim_blob(anim):
    out = bytearray([len(anim)])
    for tid, frames in anim:
        out += bytes([tid, len(frames)]) + b''.join(frames)
    return bytes(out)


def builtin_items(font_py):
    """Every pack item of the stand-in set, as {id: bytes}."""
    t0, pal0, anim0, walk0 = outdoor_tiles()
    t1, pal1, anim1, walk1 = indoor_tiles()
    sets = [outdoor_palettes(), indoor_palettes()] + [outdoor_palettes()] * 3
    items = {
        gpak.TILES0: b''.join(t0),
        gpak.TILES1: b''.join(t1),
        gpak.FONT: bytes([FONT_TILES, CAPS_PAL]) + b''.join(font_tiles(font_py)),
        gpak.WALK: walk_bits(walk0) + walk_bits(walk1),
        gpak.BGPAL: bytes([len(sets)]) + b''.join(gpak.palette(p) for s in sets for p in s),
        gpak.ANIM: anim_blob(anim0) + anim_blob(anim1),
        gpak.CHARS: chars_blob(),
        gpak.LIFT: lift_blob(LIFT_KINDS),
        gpak.START: bytes([0, 0, 1, 0, 1, 2, 0]),     # room 0, centre (256, 256) half pixels, facing down, slot 0
        gpak.SWORDPAL: b''.join(gpak.palette(p) for p in SWORD_PALS),
        gpak.OBJPAL: b''.join(gpak.palette(p) for p in OBJ_PALS),
    }
    spr = sprite_sheet()
    items[gpak.SPRITES] = bytes([len(spr)]) + b''.join(spr)
    heads = head_sets()
    items[gpak.HEADS] = bytes([len(heads)]) + b''.join(heads)
    for i, room in enumerate(make_rooms()):
        palmap = pal1 if room.tileset == 1 else pal0
        items[gpak.ROOM0 + i] = room.blob(1 if room.tileset == 1 else 0, palmap)
    return items


def main(argv):
    if len(argv) != 4:
        print(__doc__)
        return 2
    pack = gpak.build_pack(builtin_items(argv[2]))
    with open(argv[3], 'wb') as f:
        f.write(pack)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
