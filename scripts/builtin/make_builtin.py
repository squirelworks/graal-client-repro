#!/usr/bin/env python3
"""Draws the rebuilds' built-in default assets and writes common/GBuiltin.pas.

Everything here is new art drawn by this script for graal-delphi. No original
Graal graphics, levels or animations are used. The sheets only follow the
cell layout the clients expect (16 px tiles, 36 px body cells, 32 px head
cells), so files from a real install dropped next to the client replace them.

    python3 scripts/builtin/make_builtin.py

Writes common/builtin/* (the files, kept so they can be looked at) and
common/GBuiltin.pas (the same bytes as Pascal constants). Needs Pillow.
"""
import os, struct, zlib, io, sys
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, 'common', 'builtin')
os.makedirs(OUT, exist_ok=True)


def rnd(seed):
    """A tiny LCG so the art is the same on every run."""
    s = seed
    while True:
        s = (s * 1103515245 + 12345) & 0x7FFFFFFF
        yield s >> 16


# ---------------------------------------------------------------- tiles
# tile id t sits at col = t % 16 + (t // 512) * 16, row = (t // 16) % 32
T_GRASS, T_FLOWERS, T_TALLGRASS, T_PATH, T_WATER, T_WALL, T_WALLTOP, T_BUSH, \
    T_FLOOR, T_SAND, T_PATHEDGE = range(11)
PASSABLE = [T_GRASS, T_FLOWERS, T_TALLGRASS, T_PATH, T_FLOOR, T_SAND, T_PATHEDGE]


def tile_xy(t):
    return ((t % 16) + (t // 512) * 16) * 16, ((t // 16) % 32) * 16


def draw_tiles():
    im = Image.new('RGB', (2048, 512), (52, 58, 70))
    px = im.load()
    # the unused part of the sheet: a dim grid, so a missing tile shows as
    # a cell rather than as noise
    for y in range(512):
        for x in range(2048):
            if x % 16 == 0 or y % 16 == 0:
                px[x, y] = (60, 66, 80)
    r = rnd(7)

    def fill(t, base, speck=None, n=0):
        ox, oy = tile_xy(t)
        for y in range(16):
            for x in range(16):
                px[ox + x, oy + y] = base
        for _ in range(n):
            x, y = next(r) % 16, next(r) % 16
            px[ox + x, oy + y] = speck

    fill(T_GRASS, (78, 156, 70), (62, 132, 58), 18)
    fill(T_FLOWERS, (78, 156, 70), (62, 132, 58), 12)
    ox, oy = tile_xy(T_FLOWERS)
    for (fx, fy, c) in ((4, 4, (236, 220, 90)), (11, 9, (230, 120, 160)), (6, 12, (240, 240, 240))):
        for dx, dy in ((0, -1), (-1, 0), (1, 0), (0, 1)):
            px[ox + fx + dx, oy + fy + dy] = c
        px[ox + fx, oy + fy] = (250, 200, 60)
    fill(T_TALLGRASS, (66, 140, 60))
    ox, oy = tile_xy(T_TALLGRASS)
    for i in range(6):
        bx = 1 + i * 3 - (i % 2)
        for k in range(6):
            px[ox + bx + (k // 3), oy + 14 - k] = (44, 108, 46)
    fill(T_PATH, (196, 168, 112), (176, 148, 96), 14)
    fill(T_PATHEDGE, (196, 168, 112), (176, 148, 96), 8)
    ox, oy = tile_xy(T_PATHEDGE)
    for x in range(16):
        px[ox + x, oy] = (120, 150, 70)
        px[ox + x, oy + 1] = (160, 150, 96)
    fill(T_WATER, (58, 104, 196))
    ox, oy = tile_xy(T_WATER)
    for row in (3, 9):
        for x in range(16):
            if (x + row) % 8 < 4:
                px[ox + x, oy + row + ((x // 2) % 2)] = (120, 168, 232)
    fill(T_WALL, (120, 120, 132))
    ox, oy = tile_xy(T_WALL)
    for y in range(16):
        for x in range(16):
            if y % 8 == 7 or (x + (8 if (y // 8) % 2 else 0)) % 16 == 15:
                px[ox + x, oy + y] = (84, 84, 96)
            elif y % 8 == 0:
                px[ox + x, oy + y] = (150, 150, 162)
    fill(T_WALLTOP, (96, 96, 108), (110, 110, 122), 10)
    fill(T_BUSH, (78, 156, 70))
    ox, oy = tile_xy(T_BUSH)
    d = ImageDraw.Draw(im)
    d.ellipse((ox + 1, oy + 1, ox + 14, oy + 14), fill=(40, 110, 50), outline=(24, 70, 32))
    d.ellipse((ox + 4, oy + 3, ox + 8, oy + 7), fill=(70, 150, 74))
    fill(T_FLOOR, (150, 104, 62))
    ox, oy = tile_xy(T_FLOOR)
    for y in range(0, 16, 4):
        for x in range(16):
            px[ox + x, oy + y] = (118, 80, 46)
    fill(T_SAND, (226, 206, 150), (206, 186, 130), 16)
    return im


# ---------------------------------------------------------------- body
# palette roles the clients recolour: 0 outline, 1 belt, 2 clear,
# 3 shoes, 4 sleeves, 5 skin, 6 coat
BODY_PAL = [(0, 0, 0), (40, 64, 200), (0, 132, 0), (150, 30, 40), (220, 40, 40),
            (255, 196, 140), (240, 240, 240)]
CELL = 36


def body_frame(d, ox, oy, direction, step):
    """One 36x36 cell. step 0 = standing, 1..4 the walk cycle."""
    # legs: a stride for steps 1 and 3, together for 0, 2 and 4
    stride = {0: 0, 1: 2, 2: 0, 3: -2, 4: 0}[step]
    cx = ox + 18
    top = oy + 12
    if direction in (0, 2):     # up / down: legs side by side
        for side, s in ((-1, stride), (1, -stride)):
            lx = cx + side * 4 - 2
            d.rectangle((lx, top + 12, lx + 4, top + 18 + s // 2), fill=6, outline=0)
            d.rectangle((lx, top + 18 + s // 2, lx + 4, top + 21 + s // 2), fill=3, outline=0)
    else:                       # left / right: legs one behind the other
        for s in (stride, -stride):
            lx = cx - 2 + s
            d.rectangle((lx, top + 12, lx + 4, top + 19), fill=6, outline=0)
            d.rectangle((lx - (1 if direction == 1 else -1), top + 19, lx + 4 - (1 if direction == 1 else -1), top + 22), fill=3, outline=0)
    # torso
    d.rectangle((cx - 7, top, cx + 7, top + 13), fill=6, outline=0)
    d.line((cx - 6, top + 9, cx + 6, top + 9), fill=1)
    d.line((cx - 6, top + 10, cx + 6, top + 10), fill=1)
    # arms swing against the legs
    swing = stride
    if direction in (0, 2):
        for side, s in ((-1, -swing), (1, swing)):
            ax = cx + side * 9 - 2
            d.rectangle((ax, top + 1 + max(0, s), ax + 4, top + 9 + max(0, s)), fill=4, outline=0)
            d.rectangle((ax + 1, top + 9 + max(0, s), ax + 3, top + 11 + max(0, s)), fill=5, outline=0)
    else:
        ax = cx - 2 + (swing if direction == 3 else -swing)
        d.rectangle((ax, top + 1, ax + 4, top + 9), fill=4, outline=0)
        d.rectangle((ax + 1, top + 9, ax + 3, top + 11), fill=5, outline=0)


def draw_body():
    im = Image.new('P', (CELL * 4, CELL * 5), 2)
    pal = []
    for c in BODY_PAL:
        pal += list(c)
    pal += [0] * (768 - len(pal))
    im.putpalette(pal)
    d = ImageDraw.Draw(im)
    for step in range(5):
        for direction in range(4):
            body_frame(d, direction * CELL, step * CELL, direction, step)
    return im


# ---------------------------------------------------------------- head
def draw_head():
    im = Image.new('RGBA', (32, 128), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    skin, hair, line = (255, 196, 140, 255), (120, 72, 40, 255), (0, 0, 0, 255)
    for direction in range(4):
        oy = direction * 32
        d.ellipse((5, oy + 6, 26, oy + 28), fill=skin, outline=line)
        if direction == 0:      # up: the back of the head
            d.ellipse((5, oy + 5, 26, oy + 27), fill=hair, outline=line)
        elif direction == 2:    # down: the face
            d.chord((5, oy + 4, 26, oy + 22), 180, 360, fill=hair, outline=line)
            d.rectangle((11, oy + 16, 12, oy + 19), fill=line)
            d.rectangle((19, oy + 16, 20, oy + 19), fill=line)
            d.line((13, oy + 24, 18, oy + 24), fill=(170, 80, 60, 255))
        else:                   # left / right: one eye, hair at the back
            eye = 9 if direction == 1 else 21
            d.chord((5, oy + 4, 26, oy + 22), 180, 360, fill=hair, outline=line)
            bx = 17 if direction == 1 else 5
            d.ellipse((bx, oy + 7, bx + 9, oy + 22), fill=hair, outline=line)
            d.rectangle((bx + 1, oy + 8, bx + 8, oy + 14), fill=hair)
            d.rectangle((eye, oy + 16, eye + 1, oy + 19), fill=line)
    return im


def draw_sprites():
    im = Image.new('RGBA', (32, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse((0, 0, 23, 11), fill=(0, 0, 0, 255))
    # the blit has no blending: thin the shadow out to every other pixel
    px = im.load()
    for y in range(12):
        for x in range(24):
            if (x + y) % 2:
                px[x, y] = (0, 0, 0, 0)
    return im


# ---------------------------------------------------------------- status sheet
# Same geometry as the state sheet the 2.05 status routine reads (224 x 145;
# see graal_analysis client-internals/status-display.md), new art.
def heart(d, x, y, w, h, half):
    # a round shield-heart: full is red in a gold rim, half has its right side dark
    d.ellipse((x + 2, y + 2, x + w - 3, y + h - 3), fill=(40, 20, 10, 255))
    d.ellipse((x + 4, y + 4, x + w - 5, y + h - 5), fill=(236, 196, 72, 255))
    d.ellipse((x + 7, y + 7, x + w - 8, y + h - 8), fill=(200, 30, 40, 255))
    if half:
        d.pieslice((x + 7, y + 7, x + w - 8, y + h - 8), -90, 90, fill=(70, 30, 36, 255))
    d.ellipse((x + 10, y + 10, x + 10 + w // 6, y + 10 + h // 7), fill=(255, 200, 200, 255))


def draw_state():
    import font5x7
    im = Image.new('RGBA', (224, 145), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    heart(d, 0, 0, 40, 44, False)       # big full
    heart(d, 40, 0, 40, 44, True)       # big half
    heart(d, 80, 0, 31, 33, False)      # small full
    heart(d, 111, 0, 31, 33, True)      # small half
    # button (202, 0, 22, 33)
    d.rounded_rectangle((202, 0, 223, 32), 6, fill=(30, 60, 120, 255), outline=(10, 20, 40, 255))
    d.rounded_rectangle((204, 2, 221, 16), 4, fill=(70, 110, 190, 255))
    # icon strip (80, 33, 120, 16): gem at 0, bomb at 50, arrow at 100
    d.polygon([(88, 33), (95, 40), (88, 48), (81, 40)], fill=(40, 200, 90, 255), outline=(10, 60, 30, 255))
    d.ellipse((131, 35, 144, 48), fill=(30, 40, 90, 255), outline=(5, 5, 20, 255))
    d.line((140, 35, 144, 33), fill=(240, 200, 60, 255), width=2)
    d.line((181, 46, 195, 34), fill=(150, 100, 50, 255), width=2)
    d.polygon([(193, 33), (198, 33), (198, 38)], fill=(220, 220, 230, 255))
    # magic frame (0, 49, 130, 22) and fill (0, 71, 130, 10)
    d.rounded_rectangle((0, 49, 129, 70), 5, fill=(40, 30, 90, 255), outline=(10, 5, 30, 255))
    d.rectangle((20, 55, 125, 64), fill=(0, 0, 0, 0))
    for i in range(130):
        d.line((i, 71, i, 80), fill=(60 + i, 120, 230, 255))
    # digits d at (14 d, 81, 14, 16): the built-in font at 2x, black outline
    for n in range(10):
        rows = font5x7.G[str(n)]
        for ry, row in enumerate(rows):
            for rx, c in enumerate(row):
                if c == '#':
                    x, y = 14 * n + 2 + rx * 2, 81 + 1 + ry * 2
                    d.rectangle((x - 1, y - 1, x + 2, y + 2), fill=(0, 0, 0, 255))
        for ry, row in enumerate(rows):
            for rx, c in enumerate(row):
                if c == '#':
                    x, y = 14 * n + 2 + rx * 2, 81 + 1 + ry * 2
                    d.rectangle((x, y, x + 1, y + 1), fill=(255, 255, 255, 255))
    # alignment frame (0, 97, 130, 22) and fill (0, 119, 130, 10)
    d.rounded_rectangle((0, 97, 129, 118), 5, fill=(110, 30, 30, 255), outline=(30, 5, 5, 255))
    d.rectangle((20, 103, 125, 112), fill=(0, 0, 0, 0))
    d.ellipse((4, 101, 16, 113), fill=(250, 250, 250, 255), outline=(0, 0, 0, 255))
    for i in range(130):
        r = max(0, 220 - i * 2); g = min(220, i * 2); b = 60
        d.line((i, 119, i, 128), fill=(r, g, b, 255))
    return im


# ---------------------------------------------------------------- ganis
GANI_HEAD = '\n'.join('SPRITE  %3d HEAD      0 %4d  32  32 head %s' % (100 + i, i * 32, n)
                      for i, n in enumerate(('up', 'left', 'down', 'right')))
NAMES = ('up', 'left', 'down', 'right')


def gani(steps, loop):
    lines = ['GANI0001',
             'SPRITE    0 SPRITES   0    0  24  12 shadow',
             GANI_HEAD]
    for s in range(5):
        for d in range(4):
            lines.append('SPRITE  %3d BODY   %4d %4d  36  36 body %s %d' %
                         (200 + s * 4 + d, d * CELL, s * CELL, NAMES[d], s))
    lines.append('DEFAULTHEAD head0.png')
    lines.append('DEFAULTBODY body.png')
    if loop:
        lines.append('LOOP')
    lines.append('')
    lines.append('ANI')
    for s in steps:
        for d in range(4):
            bob = 1 if s in (1, 3) else 0
            lines.append('   0  12  34,  %3d   6  %2d,  %3d   8  %2d' %
                         (200 + s * 4 + d, 10 - bob, 100 + d, -4 - bob))
        lines.append('')
    lines.append('ANIEND')
    return '\n'.join(lines) + '\n'


# ---------------------------------------------------------------- arrays.dat
def arrays_dat(passable):
    def be(v):
        return struct.pack('>i', v)
    out = be(len(passable)) + b''.join(be(v) for v in passable)
    out += be(0) * 24                      # lists 1..24 empty
    return out


# ---------------------------------------------------------------- levels
B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'


def nw_level(tiles, links, signs):
    lines = ['GLEVNW01']
    for y in range(64):
        row = ''.join(B64[t >> 6] + B64[t & 63] for t in tiles[y * 64:(y + 1) * 64])
        lines.append('BOARD 0 %d 64 0 %s' % (y, row))
    for l in links:
        lines.append('LINK %s %d %d %d %d %s %s' % l)
    for (x, y, text) in signs:
        lines.append('SIGN %d %d' % (x, y))
        lines.append(text)
        lines.append('SIGNEND')
    return '\n'.join(lines) + '\n'


def start_levels():
    r = rnd(11)
    a = [T_GRASS] * 4096
    for i in range(4096):
        v = next(r) % 40
        if v == 0:
            a[i] = T_FLOWERS
        elif v == 1:
            a[i] = T_TALLGRASS
    # a wall round the edge with a gap to the east
    for i in range(64):
        for (x, y) in ((i, 0), (i, 63), (0, i)):
            a[x + y * 64] = T_WALL
        if not 28 <= i <= 35:
            a[63 + i * 64] = T_WALL
    for i in range(1, 63):
        a[i + 64] = T_WALLTOP
    # paths: one across, one down
    for x in range(1, 64):
        for y in (31, 32):
            a[x + y * 64] = T_PATH
    for y in range(2, 63):
        for x in (31, 32):
            a[x + y * 64] = T_PATH
    # a pond with a sand rim, and bushes
    for y in range(10, 22):
        for x in range(42, 56):
            dx, dy = (x - 48.5) / 7, (y - 15.5) / 6
            if dx * dx + dy * dy < 1:
                a[x + y * 64] = T_WATER
            elif dx * dx + dy * dy < 1.4:
                a[x + y * 64] = T_SAND
    for (x, y) in ((10, 10), (12, 10), (14, 10), (10, 45), (20, 50), (50, 44), (52, 46)):
        a[x + y * 64] = T_BUSH
    b = [T_SAND] * 4096
    for i in range(4096):
        if next(r) % 30 == 0:
            b[i] = T_GRASS
    for y in range(64):
        for x in range(64):
            if x > 40 and (x + y // 3) % 14 < 9:
                b[x + y * 64] = T_WATER
    for i in range(64):
        b[i] = T_WALL
        b[i + 63 * 64] = T_WALL
    for y in range(28, 36):
        for x in range(0, 30):
            b[x + y * 64] = T_PATH
    start = nw_level(a, [('start2.nw', 63, 28, 1, 8, '1', 'playery')],
                     [(30, 28, 'Welcome. This is the built-in starter level.\nDrop a Graal install next to the program to play the real one.')])
    start2 = nw_level(b, [('start.nw', 0, 28, 1, 8, '60', 'playery')], [])
    return start, start2


def png_bytes(im):
    buf = io.BytesIO()
    im.save(buf, 'PNG', optimize=True)
    return buf.getvalue()


def main():
    start, start2 = start_levels()
    files = [
        ('pics1.png', png_bytes(draw_tiles())),
        ('body.png', png_bytes(draw_body())),
        ('head0.png', png_bytes(draw_head())),
        ('sprites.png', png_bytes(draw_sprites())),
        ('state.png', png_bytes(draw_state())),
        ('idle.gani', gani([0], False).encode()),
        ('walk.gani', gani([1, 2, 3, 4], True).encode()),
        ('arrays.dat', arrays_dat(PASSABLE)),
        ('start.nw', start.encode()),
        ('start2.nw', start2.encode()),
    ]
    for name, data in files:
        with open(os.path.join(OUT, name), 'wb') as f:
            f.write(data)
    pas = ['{ GBuiltin: the default assets built into the client. GENERATED by',
           '  scripts/builtin/make_builtin.py from new art drawn by that script; do',
           '  not edit by hand. A file of the same name next to the client, or in',
           '  its install folders, is used instead of these. }',
           'unit GBuiltin;', '', '{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}', '',
           'interface', '',
           '{ The built-in file Name (any case; for images, any of .png / .gif /',
           '  .bmp matches the built-in .png), or False when there is none. }',
           'function BuiltinFile(const Name: string; out Data: string): Boolean;',
           '{ The names of the built-in files, for listings and tests. }',
           'function BuiltinCount: Integer;', 'function BuiltinName(I: Integer): string;', '',
           'implementation', '', 'uses', '  SysUtils;', '']
    for i, (name, data) in enumerate(files):
        pas.append('const')
        pas.append('  F%d: array[0..%d] of Byte = (' % (i, len(data) - 1))
        hexes = ['$%02x' % b for b in data]
        for j in range(0, len(hexes), 18):
            pas.append('    ' + ','.join(hexes[j:j + 18]) + (',' if j + 18 < len(hexes) else ');'))
        pas.append('')
    pas.append('const')
    pas.append('  Names: array[0..%d] of string = (' % (len(files) - 1))
    pas.append(',\n'.join("    '%s'" % n for n, _ in files) + ');')
    pas.append('')
    pas.append('function Bytes(I: Integer): string;')
    pas.append('  procedure Take(const B: array of Byte);')
    pas.append('  begin')
    pas.append('    SetLength(Result, Length(B));')
    pas.append('    if Length(B) > 0 then Move(B[0], Result[1], Length(B));')
    pas.append('  end;')
    pas.append('begin')
    pas.append("  Result := '';")
    pas.append('  case I of')
    for i in range(len(files)):
        pas.append('    %d: Take(F%d);' % (i, i))
    pas.append('  end;')
    pas.append('end;')
    pas.append('')
    pas.append('''function BuiltinCount: Integer;
begin
  Result := Length(Names);
end;

function BuiltinName(I: Integer): string;
begin
  Result := Names[I];
end;

function BuiltinFile(const Name: string; out Data: string): Boolean;
var
  I: Integer;
  N, Ext, Base: string;
begin
  Result := False;
  Data := '';
  N := LowerCase(ExtractFileName(Name));
  Ext := ExtractFileExt(N);
  Base := Copy(N, 1, Length(N) - Length(Ext));
  for I := 0 to High(Names) do
    if (Names[I] = N) or (((Ext = '.gif') or (Ext = '.bmp') or (Ext = '.png') or (Ext = '')) and
      (Names[I] = Base + '.png')) then
    begin
      Data := Bytes(I);
      Result := True;
      Exit;
    end;
end;

end.''')
    with open(os.path.join(ROOT, 'common', 'GBuiltin.pas'), 'w') as f:
        f.write('\n'.join(pas) + '\n')
    for name, data in files:
        print('%-12s %6d bytes' % (name, len(data)))


def write_font():
    import font5x7
    vals = []
    for c in range(32, 127):
        rows = font5x7.G[chr(c)]
        for r in rows:
            v = 0
            for i, ch in enumerate(r):
                if ch == '#':
                    v |= 1 << (4 - i)
            vals.append(v)
    body = []
    for j in range(0, len(vals), 21):
        body.append('    ' + ','.join('$%02x' % v for v in vals[j:j + 21]) +
                    (',' if j + 21 < len(vals) else ');'))
    pas = '''{ GFont: the 5x7 text of the built-in screens. GENERATED by
  scripts/builtin/make_builtin.py from scripts/builtin/font5x7.py, a font
  drawn for graal-delphi; do not edit by hand. }
unit GFont;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  GSurface;

const
  GlyphW = 6; { 5 columns and a space }
  GlyphH = 8; { 7 rows and a space }

{ Pixels across S at Scale. }
function TextWidth(const S: string; Scale: Integer): Integer;
{ Draws S with its top-left at (X, Y); characters outside ' '..'~' show
  as '?'. }
procedure DrawText(Dest: TGSurface; X, Y: Integer; const S: string;
  Color: Cardinal; Scale: Integer);

implementation

const
  Rows: array[0..%d] of Byte = (
%s

function TextWidth(const S: string; Scale: Integer): Integer;
begin
  Result := Length(S) * GlyphW * Scale;
end;

procedure DrawText(Dest: TGSurface; X, Y: Integer; const S: string;
  Color: Cardinal; Scale: Integer);
var
  I, R, C, G: Integer;
  B: Byte;
begin
  for I := 1 to Length(S) do
  begin
    G := Ord(S[I]);
    if (G < 32) or (G > 126) then G := Ord('?');
    for R := 0 to 6 do
    begin
      B := Rows[(G - 32) * 7 + R];
      for C := 0 to 4 do
        if B and (1 shl (4 - C)) <> 0 then
          Dest.FillRect(X + ((I - 1) * GlyphW + C) * Scale, Y + R * Scale, Scale, Scale, Color);
    end;
  end;
end;

end.
''' % (len(vals) - 1, '\n'.join(body))
    with open(os.path.join(ROOT, 'common', 'GFont.pas'), 'w') as f:
        f.write(pas)


if __name__ == '__main__':
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    main()
    write_font()
