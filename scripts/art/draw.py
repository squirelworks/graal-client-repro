"""The drawing kit of the replacement art: text, symbols, scenes, the mascot.

Everything here is drawn by code for graal-delphi. Scenes are laid out
from the project's own tile sheet (common/builtin/pics1.png, drawn by
scripts/builtin/make_builtin.py); the mascot is the squirrel of the Seihai
default art (seihai-core 0.1.9), drawn again here with shapes. No picture
of an original client is read by anything in this file.
"""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, 'scripts', 'builtin'))
from font5x7 import G as FONT  # noqa: E402

# ------------------------------------------------------------------ palette
FOREST = (28, 74, 46)
LEAF = (64, 140, 72)
MOSS = (108, 170, 84)
BARK = (110, 70, 40)
ACORN = (196, 120, 52)
CAP = (122, 82, 44)
CREAM = (246, 232, 196)
INK = (34, 28, 24)
SKY = (120, 176, 214)
STONE = (150, 156, 160)
RED = (200, 56, 48)
GOLD = (232, 188, 64)
BLUE = (64, 112, 200)


def rnd(seed):
    """A small LCG, so every picture is the same on every run."""
    s = seed & 0x7FFFFFFF
    while True:
        s = (s * 1103515245 + 12345) & 0x7FFFFFFF
        yield s >> 16


def seed_of(text):
    h = 2166136261
    for c in text.encode('utf-8'):
        h = ((h ^ c) * 16777619) & 0xFFFFFFFF
    return h


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


# ------------------------------------------------------------------ text

def text_size(text, scale=1):
    w = 0
    for ch in text:
        w += 6 * scale
    return max(0, w - scale), 7 * scale


def draw_text(img, x, y, text, color, scale=1, shadow=None, outline=None):
    """Pixel text from the project's 5x7 font."""
    d = ImageDraw.Draw(img)

    def ink(ox, oy, col):
        cx = x + ox
        for ch in text:
            g = FONT.get(ch) or FONT.get(ch.upper()) or FONT.get('?')
            for r, row in enumerate(g):
                for c, v in enumerate(row):
                    if v == '#':
                        d.rectangle([cx + c * scale, y + oy + r * scale,
                                     cx + c * scale + scale - 1, y + oy + r * scale + scale - 1], fill=col)
            cx += 6 * scale
    if outline is not None:
        for ox, oy in ((-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, 1), (-1, 1), (1, -1)):
            ink(ox * max(1, scale // 2), oy * max(1, scale // 2), outline)
    if shadow is not None:
        ink(max(1, scale // 2), max(1, scale // 2), shadow)
    ink(0, 0, color)


def fit_scale(text, w, h, maxscale=8):
    s = maxscale
    while s > 1:
        tw, th = text_size(text, s)
        if tw <= w and th <= h:
            return s
        s -= 1
    return 1


def centered_text(img, box, text, color, maxscale=8, outline=None, shadow=None):
    x0, y0, x1, y1 = box
    s = fit_scale(text, x1 - x0, y1 - y0, maxscale)
    tw, th = text_size(text, s)
    draw_text(img, x0 + (x1 - x0 - tw) // 2, y0 + (y1 - y0 - th) // 2, text, color, s,
              outline=outline, shadow=shadow)


# ------------------------------------------------------------------ tiles

_TILES = None


def tiles():
    global _TILES
    if _TILES is None:
        _TILES = Image.open(os.path.join(ROOT, 'common', 'builtin', 'pics1.png')).convert('RGB')
    return _TILES


def tile(t):
    x = ((t % 16) + (t // 512) * 16) * 16
    y = ((t // 16) % 32) * 16
    return tiles().crop((x, y, x + 16, y + 16))


T_GRASS, T_FLOWERS, T_TALLGRASS, T_PATH, T_WATER, T_WALL, T_WALLTOP, T_BUSH, \
    T_FLOOR, T_SAND, T_PATHEDGE = range(11)
O_BUSH, O_STUMP, O_POT, O_SIGN, O_STONE, O_CHEST = 32, 34, 36, 40, 44, 64


def landscape(seed, cols=64, rows=64):
    """A board of tile ids: meadow, a winding path, a pond, bushes, trees."""
    r = rnd(seed)
    a = [T_GRASS] * (cols * rows)
    for i in range(len(a)):
        v = next(r) % 30
        a[i] = T_FLOWERS if v == 0 else T_TALLGRASS if v == 1 else T_GRASS
    # path: a sine across
    ph = (next(r) % 100) / 16.0
    for x in range(cols):
        yc = int(rows / 2 + math.sin(x / 7.0 + ph) * rows / 6)
        for y in range(yc - 1, yc + 2):
            if 0 <= y < rows:
                a[x + y * cols] = T_PATH
    # a pond
    px, py = 8 + next(r) % max(1, cols - 20), 4 + next(r) % max(1, rows // 3)
    for y in range(rows):
        for x in range(cols):
            dx, dy = (x - px) / 6.0, (y - py) / 4.0
            q = dx * dx + dy * dy
            if q < 1:
                a[x + y * cols] = T_WATER
            elif q < 1.5 and a[x + y * cols] != T_PATH:
                a[x + y * cols] = T_SAND
    objs = []
    for _ in range(cols * rows // 90):
        x, y = next(r) % (cols - 1), next(r) % (rows - 1)
        if all(a[x + dx + (y + dy) * cols] in (T_GRASS, T_FLOWERS, T_TALLGRASS)
               for dx in (0, 1) for dy in (0, 1)):
            b = (O_BUSH, O_BUSH, O_STONE, O_STUMP, O_POT)[next(r) % 5]
            for k, (dx, dy) in enumerate(((0, 0), (1, 0), (0, 1), (1, 1))):
                a[x + dx + (y + dy) * cols] = b + (k % 2) + 16 * (k // 2)
            objs.append((x, y))
    return a


def render_board(a, cols, rows):
    img = Image.new('RGB', (cols * 16, rows * 16))
    cache = {}
    for y in range(rows):
        for x in range(cols):
            t = a[x + y * cols]
            if t not in cache:
                cache[t] = tile(t)
            img.paste(cache[t], (x * 16, y * 16))
    return img


def scene(w, h, seed, zoom=1, dark=0.0):
    """A top-down meadow of the project's own tiles, w x h pixels."""
    cols = (w // (16 * zoom)) + 2
    rows = (h // (16 * zoom)) + 2
    img = render_board(landscape(seed, cols, rows), cols, rows)
    if zoom != 1:
        img = img.resize((img.width * zoom, img.height * zoom), Image.NEAREST)
    img = img.crop((8, 8, 8 + w, 8 + h))
    if dark:
        img = Image.blend(img, Image.new('RGB', img.size, FOREST), dark)
    return img


# ------------------------------------------------------------------ shapes

def bevel(img, box, face, light=None, dark=None, width=2, radius=4):
    d = ImageDraw.Draw(img)
    light = light or mix(face, (255, 255, 255), 0.45)
    dark = dark or mix(face, (0, 0, 0), 0.5)
    x0, y0, x1, y1 = box
    d.rounded_rectangle(box, radius, fill=dark)
    d.rounded_rectangle((x0, y0, x1 - width, y1 - width), radius, fill=light)
    d.rounded_rectangle((x0 + width, y0 + width, x1 - width, y1 - width), max(0, radius - 1), fill=face)


def panel(img, box, alpha=150, color=(14, 40, 26)):
    over = Image.new('RGBA', img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(over)
    d.rounded_rectangle(box, 8, fill=color + (alpha,), outline=CREAM + (200,), width=1)
    base = img.convert('RGBA')
    base.alpha_composite(over)
    return base.convert(img.mode) if img.mode != 'RGBA' else base


def acorn(img, cx, cy, size, shade=0.0):
    """The project's acorn: a brown nut under a darker cap with a stem."""
    d = ImageDraw.Draw(img)
    s = size
    nut = mix(ACORN, (0, 0, 0), shade)
    cap = mix(CAP, (0, 0, 0), shade)
    d.ellipse((cx - s * 0.42, cy - s * 0.18, cx + s * 0.42, cy + s * 0.5), fill=nut, outline=INK)
    d.pieslice((cx - s * 0.5, cy - s * 0.42, cx + s * 0.5, cy + s * 0.12), 180, 360, fill=cap, outline=INK)
    d.rectangle((cx - s * 0.5, cy - s * 0.16, cx + s * 0.5, cy - s * 0.06), fill=cap, outline=INK)
    d.line((cx, cy - s * 0.42, cx + s * 0.08, cy - s * 0.56), fill=INK, width=max(1, int(s / 12)))
    if s >= 12:
        d.ellipse((cx - s * 0.26, cy + s * 0.0, cx - s * 0.12, cy + s * 0.22), fill=mix(nut, (255, 255, 255), 0.4))


def squirrel(img, box, pose='face'):
    """The Seihai squirrel, as a face (portrait) or sitting (full)."""
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    d = ImageDraw.Draw(img)
    fur = (200, 112, 52)
    dark = (128, 66, 30)
    belly = (246, 222, 178)
    if pose == 'full' and h > w * 1.3:
        # tail behind, body, head on top
        tw = w * 0.55
        d.ellipse((x0 + w * 0.45, y0 + h * 0.18, x0 + w * 0.45 + tw, y0 + h * 0.8), fill=dark, outline=INK)
        d.ellipse((x0 + w * 0.5, y0 + h * 0.2, x0 + w * 0.42 + tw, y0 + h * 0.74), fill=fur)
        d.ellipse((x0 + w * 0.12, y0 + h * 0.42, x0 + w * 0.7, y0 + h * 0.95), fill=fur, outline=INK)
        d.ellipse((x0 + w * 0.24, y0 + h * 0.52, x0 + w * 0.56, y0 + h * 0.9), fill=belly)
        acorn(img, int(x0 + w * 0.4), int(y0 + h * 0.6), max(6, int(w * 0.22)))
        squirrel(img, (int(x0 + w * 0.05), int(y0 + h * 0.08), int(x0 + w * 0.75), int(y0 + h * 0.08 + w * 0.7)))
        return
    s = min(w, h)
    cx, cy = x0 + w / 2, y0 + h / 2 + s * 0.06
    r = s * 0.4
    # ears
    for sx in (-1, 1):
        d.polygon([(cx + sx * r * 0.85, cy - r * 0.35), (cx + sx * r * 0.55, cy - r * 1.15),
                   (cx + sx * r * 0.2, cy - r * 0.6)], fill=dark, outline=INK)
    d.ellipse((cx - r, cy - r * 0.85, cx + r, cy + r * 0.85), fill=fur, outline=INK)
    d.ellipse((cx - r * 0.55, cy + r * 0.0, cx + r * 0.55, cy + r * 0.8), fill=belly)
    e = max(1, r * 0.16)
    for sx in (-1, 1):
        d.ellipse((cx + sx * r * 0.38 - e, cy - r * 0.25 - e, cx + sx * r * 0.38 + e, cy - r * 0.25 + e), fill=INK)
        if s >= 24:
            d.ellipse((cx + sx * r * 0.38 - e * 0.2, cy - r * 0.25 - e * 0.7, cx + sx * r * 0.38 + e * 0.35,
                       cy - r * 0.25 - e * 0.15), fill=(255, 255, 255))
    d.ellipse((cx - e, cy + r * 0.12 - e * 0.7, cx + e, cy + r * 0.12 + e * 0.7), fill=(90, 40, 30))
    if s >= 16:
        d.rectangle((cx - e * 0.8, cy + r * 0.3, cx + e * 0.8, cy + r * 0.5), fill=(255, 255, 255), outline=INK)


# ------------------------------------------------------------------ symbols
# Small pictures for buttons and toolbars, each drawn into a w x h box.

def _sym_page(d, w, h, col=(255, 255, 255)):
    d.polygon([(w * 0.2, h * 0.08), (w * 0.62, h * 0.08), (w * 0.82, h * 0.28), (w * 0.82, h * 0.92),
               (w * 0.2, h * 0.92)], fill=col, outline=INK)
    d.line([(w * 0.62, h * 0.08), (w * 0.62, h * 0.28), (w * 0.82, h * 0.28)], fill=INK)


def symbol(img, box, kind, enabled=True):
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    layer = Image.new('RGBA', (w * 4, h * 4), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    W, H = w * 4, h * 4
    lw = max(2, min(W, H) // 10)
    k = kind
    if k == 'page':
        _sym_page(d, W, H)
    elif k == 'edit':
        _sym_page(d, W, H)
        d.line([(W * 0.3, H * 0.8), (W * 0.9, H * 0.2)], fill=GOLD, width=lw + 2)
        d.line([(W * 0.3, H * 0.8), (W * 0.38, H * 0.72)], fill=INK, width=lw)
    elif k == 'export':
        _sym_page(d, W, H)
        d.line([(W * 0.05, H * 0.6), (W * 0.6, H * 0.6)], fill=BLUE, width=lw)
        d.polygon([(W * 0.6, H * 0.42), (W * 0.85, H * 0.6), (W * 0.6, H * 0.78)], fill=BLUE)
    elif k == 'disk':
        d.rectangle((W * 0.12, H * 0.1, W * 0.88, H * 0.9), fill=(70, 96, 150), outline=INK, width=2)
        d.rectangle((W * 0.28, H * 0.1, W * 0.72, H * 0.4), fill=(220, 220, 226), outline=INK)
        d.rectangle((W * 0.25, H * 0.58, W * 0.75, H * 0.9), fill=CREAM, outline=INK)
    elif k == 'folder':
        d.polygon([(W * .06, H * .2), (W * .4, H * .2), (W * .48, H * .32), (W * .94, H * .32), (W * .94, H * .88),
                   (W * .06, H * .88)], fill=GOLD, outline=INK)
        d.polygon([(W * .06, H * .88), (W * .2, H * .45), (W * .99, H * .45), (W * .86, H * .88)],
                  fill=mix(GOLD, (255, 255, 255), .35), outline=INK)
    elif k == 'close':
        d.ellipse((W * .08, H * .08, W * .92, H * .92), fill=RED, outline=INK, width=2)
        d.line([(W * .3, H * .3), (W * .7, H * .7)], fill=(255, 255, 255), width=lw + 1)
        d.line([(W * .7, H * .3), (W * .3, H * .7)], fill=(255, 255, 255), width=lw + 1)
    elif k in ('right', 'left', 'enter', 'link'):
        sx = -1 if k == 'left' else 1
        cx = W / 2
        col = BLUE if k != 'link' else LEAF
        d.rectangle((cx - W * .36, H * .38, cx + W * .1 * sx, H * .62), fill=col, outline=INK)
        tip = cx + sx * W * .42
        base = cx + sx * W * .02
        d.polygon([(base, H * .15), (tip, H * .5), (base, H * .85)], fill=col, outline=INK)
        if k == 'enter':
            d.rectangle((W * .78, H * .08, W * .94, H * .92), fill=BARK, outline=INK)
    elif k == 'play':
        d.polygon([(W * .2, H * .1), (W * .85, H * .5), (W * .2, H * .9)], fill=LEAF, outline=INK)
    elif k == 'scissors':
        d.line([(W * .25, H * .05), (W * .65, H * .62)], fill=STONE, width=lw)
        d.line([(W * .75, H * .05), (W * .35, H * .62)], fill=STONE, width=lw)
        d.ellipse((W * .05, H * .6, W * .45, H * .95), outline=RED, width=lw)
        d.ellipse((W * .55, H * .6, W * .95, H * .95), outline=RED, width=lw)
    elif k == 'copy':
        d.rectangle((W * .08, H * .06, W * .62, H * .7), fill=(255, 255, 255), outline=INK)
        d.rectangle((W * .38, H * .3, W * .92, H * .94), fill=CREAM, outline=INK)
    elif k == 'paste':
        d.rectangle((W * .12, H * .14, W * .78, H * .94), fill=BARK, outline=INK)
        d.rectangle((W * .3, H * .06, W * .6, H * .22), fill=STONE, outline=INK)
        d.rectangle((W * .42, H * .38, W * .94, H * .9), fill=(255, 255, 255), outline=INK)
    elif k == 'brush':
        d.line([(W * .8, H * .1), (W * .4, H * .6)], fill=BARK, width=lw + 2)
        d.ellipse((W * .1, H * .5, W * .5, H * .92), fill=RED, outline=INK)
    elif k == 'grid':
        for i in range(4):
            for j in range(4):
                d.rectangle((W * (.08 + i * .22), H * (.08 + j * .22), W * (.26 + i * .22), H * (.26 + j * .22)),
                            fill=(LEAF, MOSS, ACORN, STONE)[(i + j) % 4], outline=INK)
    elif k == 'lamp':
        d.ellipse((W * .25, H * .1, W * .75, H * .62), fill=GOLD, outline=INK, width=2)
        d.rectangle((W * .38, H * .62, W * .62, H * .88), fill=STONE, outline=INK)
    elif k == 'dash':
        d.line([(W * .1, H * .5), (W * .9, H * .5)], fill=INK, width=max(lw, H // 3))
    elif k == 'cup':
        d.polygon([(W * .1, H * .1), (W * .9, H * .1), (W * .62, H * .55), (W * .38, H * .55)], fill=GOLD, outline=INK)
        d.rectangle((W * .44, H * .55, W * .56, H * .8), fill=GOLD, outline=INK)
        d.rectangle((W * .25, H * .8, W * .75, H * .92), fill=GOLD, outline=INK)
    elif k == 'keyboard':
        d.rounded_rectangle((W * .04, H * .25, W * .96, H * .85), 6, fill=(220, 220, 226), outline=INK, width=2)
        for j in range(3):
            for i in range(7):
                d.rectangle((W * (.1 + i * .12), H * (.33 + j * .16), W * (.18 + i * .12), H * (.43 + j * .16)),
                            fill=STONE)
    elif k == 'joystick':
        d.rounded_rectangle((W * .1, H * .62, W * .9, H * .92), 6, fill=(220, 220, 226), outline=INK, width=2)
        d.line([(W * .5, H * .7), (W * .5, H * .25)], fill=INK, width=lw + 2)
        d.ellipse((W * .36, H * .06, W * .64, H * .34), fill=RED, outline=INK)
    elif k == 'sign':
        d.rectangle((W * .1, H * .12, W * .9, H * .6), fill=(214, 168, 104), outline=INK)
        d.rectangle((W * .44, H * .6, W * .56, H * .95), fill=BARK)
        for j in (.26, .4):
            d.line([(W * .22, H * j), (W * .78, H * j)], fill=BARK, width=max(1, lw // 2))
    elif k == 'refresh':
        d.arc((W * .12, H * .12, W * .88, H * .88), 30, 330, fill=LEAF, width=lw + 2)
        d.polygon([(W * .7, H * .05), (W * .95, H * .3), (W * .66, H * .38)], fill=LEAF)
    elif k == 'warning':
        d.polygon([(W * .5, H * .06), (W * .95, H * .92), (W * .05, H * .92)], fill=GOLD, outline=INK)
        d.rectangle((W * .45, H * .32, W * .55, H * .66), fill=INK)
        d.rectangle((W * .45, H * .74, W * .55, H * .84), fill=INK)
    elif k == 'home':
        d.polygon([(W * .5, H * .08), (W * .94, H * .5), (W * .06, H * .5)], fill=RED, outline=INK)
        d.rectangle((W * .18, H * .5, W * .82, H * .92), fill=CREAM, outline=INK)
        d.rectangle((W * .42, H * .62, W * .58, H * .92), fill=BARK)
    elif k == 'acorn':
        acorn(layer, W // 2, H // 2, int(min(W, H) * .85))
    elif k == 'squirrel':
        squirrel(layer, (0, 0, W, H))
    elif k == 'go':
        d.rounded_rectangle((W * .04, H * .08, W * .96, H * .92), int(H * .3), fill=LEAF, outline=INK, width=2)
    else:  # a neutral mark: a leaf
        d.ellipse((W * .15, H * .2, W * .85, H * .8), fill=LEAF, outline=INK, width=2)
        d.line([(W * .2, H * .75), (W * .8, H * .25)], fill=FOREST, width=lw)
    small = layer.resize((w, h), Image.LANCZOS)
    # hard edges for small glyphs: alpha to 0/255
    a = small.getchannel('A').point(lambda v: 255 if v >= 110 else 0)
    small.putalpha(a)
    if not enabled:
        g = small.convert('LA').convert('RGBA')
        g.putalpha(a)
        small = Image.blend(g, Image.new('RGBA', g.size, (160, 160, 160, 255)), 0.35)
        small.putalpha(a)
    img.paste(small, (x0, y0), small)
    if kind == 'go':
        centered_text(img, (x0 + 2, y0 + 2, x1 - 2, y1 - 2), 'GO', CREAM, 3, outline=INK)
