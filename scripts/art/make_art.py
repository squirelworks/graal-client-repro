#!/usr/bin/env python3
"""Draws graal-delphi's own art in place of every picture and level the
builds carried from the original clients' programs.

    python3 -I scripts/art/make_art.py            rewrite every build's resources
    python3 -I scripts/art/make_art.py --check    exit 1 if any would change
    python3 -I scripts/art/make_art.py --list F   write the inventory (docs/art.md table)
    python3 -I scripts/art/make_art.py --samples DIR   contact sheets of the new art

What a resource is comes from its name (SCREENIMG1, BUTTON2, the form and
component a picture sits in: docs/art.md lists each) and its shape. What a
replacement keeps from the file it replaces is only that shape: format,
width and height, bit depth and palette size, row order, the transparent
key colour of a VCL glyph, icon sizes and cursor hot spots, the piece
rectangles of a Torque bitmap array, and a level's links. The pixels,
boards and words are drawn here (scripts/art/draw.py), so running this on
its own output gives the same bytes again (`--check`).

Resources are found in every place a build keeps them (scripts/art/
containers.py): files under <build>/res/ and <build>/src/res/, the
generated Res*.pas units and common/GRes20x.pas, the .res files the .dpr
links, and the program icons. Text (forms' layout and captions, string
tables, character lists, language files) is left as it is.
"""
import collections
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from PIL import Image, ImageDraw  # noqa: E402

import containers as C  # noqa: E402
import dfm  # noqa: E402
import draw as D  # noqa: E402
import imgfmt  # noqa: E402
import levels  # noqa: E402

# ------------------------------------------------------------------ what is it

# Form pictures: (form, component) -> what the picture shows, read off the
# old forms by eye and drawn anew. Forms differ between versions only in
# which of these they hold.
GLYPHS = {
    ('ADVENTURE', 'SPEEDBUTTON14'): 'enter',
    ('ADVENTURE', 'SPEEDBUTTON15'): 'disk',
    ('ADVENTURE', 'SPEEDBUTTON16'): 'close',
    ('ADVENTURE', 'SPEEDBUTTON11'): 'export',
    ('ADVENTURE', 'PLAYBUTTON'): 'play',
    ('ADVENTURE', 'SPEEDBUTTON1'): 'page',
    ('ADVENTURE', 'SPEEDBUTTON10'): 'right',
    ('ADVENTURE', 'SPEEDBUTTON12'): 'brush',
    ('ADVENTURE', 'SPEEDBUTTON13'): 'grid',
    ('ADVENTURE', 'SPEEDBUTTON17'): 'lamp',
    ('ADVENTURE', 'SPEEDBUTTON2'): 'folder',
    ('ADVENTURE', 'SPEEDBUTTON4'): 'disk',
    ('ADVENTURE', 'SPEEDBUTTON5'): 'dash',
    ('ADVENTURE', 'SPEEDBUTTON6'): 'scissors',
    ('ADVENTURE', 'SPEEDBUTTON7'): 'copy',
    ('ADVENTURE', 'SPEEDBUTTON8'): 'paste',
    ('CONTROLSFRAME', 'IMAGE1'): 'keyboard',
    ('CONTROLSFRAME', 'IMAGE2'): 'joystick',
    ('CONTROLSFRAME', 'IMAGE3'): 'poses',
    ('EDITPERSON', 'BITBTN1'): 'lamp',
    ('LINKOPTIONS', 'IMAGE1'): 'link',
    ('PERSONACTION', 'SIGNBUTTON'): 'sign',
    ('PERSONACTION', 'TESTBUTTON'): 'refresh',
    ('RECONNECTFRAME', 'IMAGE1'): 'warning',
    ('SERVERLISTFRAME', 'BUTTON1'): 'strip',
    ('SERVERLISTFRAME', 'PAINTBUTTON1'): 'strip',
    ('SERVERLISTFRAME', 'SPEEDBUTTON2'): 'gostrip',
    ('SERVERMESSAGE', 'SPEEDBUTTON1'): 'left',
    ('SERVERMESSAGE', 'SPEEDBUTTON2'): 'right',
    ('SERVERMESSAGE', 'SPEEDBUTTON3'): 'close',
    ('SERVERMESSAGE', 'SPEEDBUTTON4'): 'refresh',
    ('SERVERMESSAGE', 'SPEEDBUTTON5'): 'home',
    ('OPTIONS', 'IMAGE1'): 'thumb',
    ('OPTIONS', 'IMAGE2'): 'thumb',
    ('OPTIONS', 'EDITBUTTON'): 'edit',
    ('WAABOUT', 'IMAGE1'): 'acorn',
    ('ADVENTURE', 'SPEEDBUTTON3'): 'disk',
    ('ADVENTURE', 'SPEEDBUTTON9'): 'close',
    ('ADVENTURE', 'SPEEDBUTTON18'): 'page',
    ('PROFILEEDIT', 'SPEEDBUTTON1'): 'play',
}

# Buttons named for what they do, in any form.
VERBS = (('DELETE', 'close'), ('REMOVE', 'close'), ('LOAD', 'folder'), ('OPEN', 'folder'),
         ('SAVE', 'disk'), ('EDIT', 'edit'), ('SIGN', 'sign'), ('CLOSE', 'close'))

# The 1.x and beta start dialogs (ConnectFrame) hold credit pictures, a
# trophy and a character drawing; which is which goes by size.
CURSORS = {32761: 'hand', 32762: 'wait', 32763: 'multidrag', 32764: 'vsplit',
           32765: 'hsplit', 32766: 'drag', 32767: 'nodrop'}

SCREENS = ('SCREENIMG', 'LOADINGSCREEN', 'STARTIMAGE', 'GRAALV4SCREEN')


def base_name(hint):
    n = hint.replace('\\', '/').split('/')[-1]
    n = re.sub(r'\.[A-Za-z0-9]+$', '', n)
    m = re.match(r'^B([A-Z0-9_]+?)_[0-9a-f]{8}$', n)
    if m:
        n = m.group(1)
    return n.upper()


def form_key(form_hint, path):
    f = base_name(form_hint)
    if f.startswith('T') and f[1:] in {k[0] for k in GLYPHS} | {'CONNECTFRAME'}:
        f = f[1:]
    comp = path.split('.')[-1].upper()
    return f, comp


def picture_role(form, comp, w, h):
    # the 2.x picture buttons: two halves of a wide bar, whatever the form
    if w >= 150 and h <= 40:
        return 'strip'
    if (w, h) == (56, 26):
        return 'gostrip'
    r = GLYPHS.get((form, comp))
    if r:
        return r
    for verb, sym in VERBS:
        if comp.startswith(verb) and w <= 40 and h <= 40:
            return sym
    if form == 'CONNECTFRAME':
        if h >= 200 and w < h:
            return 'portrait-full'
        if w >= 60 and h >= 30:
            return 'banner'
        if w <= 30 and h > w:
            return 'cup'
        return 'portrait'
    if w >= 150 and h <= 40:
        return 'strip'
    if w >= 60 and h >= 40:
        return 'banner'
    return 'leaf'


# ------------------------------------------------------------------ drawing

BTNFACE = (192, 192, 192)
TITLE = 'GRAAL-DELPHI'


def states(w, h):
    """How many glyph cells a VCL glyph holds side by side."""
    if h and w >= 2 * h - 2 and w // max(1, h) <= 4:
        return max(1, int(round(w / float(h))))
    return 1


def draw_glyph(kind, w, h):
    img = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    n = states(w, h)
    cw = w // n
    for i in range(n):
        D.symbol(img, (i * cw, 0, i * cw + cw, h), kind, enabled=(i != 1))
    return img


def draw_strip(w, h, label=''):
    """A picture button: left half up, right half down."""
    img = Image.new('RGBA', (w, h), (0, 0, 0, 255))
    half = w // 2
    for i, (face, off) in enumerate(((D.MOSS, 0), (D.mix(D.MOSS, (0, 0, 0), .25), 1))):
        x0 = i * half
        D.bevel(img, (x0, 0, x0 + half - 1, h - 1), face, radius=max(2, h // 4), width=2)
        if label:
            D.centered_text(img, (x0 + 2 + off, 2 + off, x0 + half - 2 + off, h - 2 + off), label, D.CREAM, 3,
                            outline=D.INK)
    return img


def draw_banner(w, h, seed, bg=BTNFACE):
    img = Image.new('RGBA', (w, h), bg + (255,))
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, w - 1, h - 1), outline=D.mix(bg, (0, 0, 0), .3))
    a = min(h - 4, w // 4)
    if a >= 10:
        D.acorn(img, 4 + a // 2, h // 2, a)
        tx = 8 + a
    else:
        tx = 2
    lines = [TITLE, 'A FAN REBUILD'] if h >= 24 else [TITLE]
    lh = (h - 4) // len(lines)
    for i, t in enumerate(lines):
        D.centered_text(img, (tx, 2 + i * lh, w - 2, 2 + (i + 1) * lh), t,
                        D.BARK if i == 0 else D.FOREST, 6)
    return img


def draw_portrait(w, h, full=False, bg=BTNFACE):
    img = Image.new('RGBA', (w, h), bg + (255,))
    D.squirrel(img, (1, 1, w - 1, h - 1), 'full' if full else 'face')
    return img


def draw_poses(w, h):
    """A column of the built-in player in each direction."""
    img = Image.new('RGBA', (w, h), BTNFACE + (255,))
    body = Image.open(os.path.join(C.ROOT, 'common', 'builtin', 'body.png')).convert('RGBA')
    head = Image.open(os.path.join(C.ROOT, 'common', 'builtin', 'head0.png')).convert('RGBA')
    cell = w
    n = max(1, h // cell)
    for i in range(n):
        d = i % 4
        fig = Image.new('RGBA', (32, 48), (0, 0, 0, 0))
        fig.alpha_composite(body.crop((0, d * 36, 32, d * 36 + 32)), (0, 16))
        fig.alpha_composite(head.crop((0, d * 32, 32, d * 32 + 32)), (0, 0))
        fig = fig.resize((cell, int(cell * 1.5)), Image.NEAREST).crop((0, 0, cell, cell))
        img.alpha_composite(fig, (0, i * cell))
    return img


def draw_screen(name, w, h, build):
    seed = D.seed_of(name + str(w) + 'x' + str(h))
    zoom = 1
    if name == 'STARTIMAGE':
        img = Image.new('RGB', (w, h), (98, 62, 34))
        d = ImageDraw.Draw(img)
        r = D.rnd(seed)
        for y in range(h):  # wood grain
            v = (next(r) % 9) - 4
            d.line((0, y, w, y), fill=D.mix((98 + v, 62 + v, 34), (60, 36, 18), (y % 23) / 60.0))
        D.bevel(img, (6, 6, w - 7, h - 7), (120, 78, 42), radius=10, width=3)
        D.centered_text(img, (0, 18, w, 70), TITLE + ' 3D', D.CREAM, 5, outline=D.INK)
        tops = (96, 135, 171, 208, 246)
        labels = ('Nickname', 'Server', 'Port', 'Account', 'Password')
        for t, lab in zip(tops, labels):
            D.draw_text(img, 26, t + 8, lab, D.CREAM, 1, shadow=D.INK)
            d.rectangle((114, t, 114 + 184, t + 23), fill=(36, 22, 12), outline=D.CREAM)
        return img.convert('RGBA')
    img = D.scene(w, h, seed, zoom=zoom, dark=0.35)
    top = max(18, h // 6)
    img = D.panel(img, (8, 6, w - 9, 6 + top), alpha=170)
    D.centered_text(img, (12, 8, w - 12, 4 + top), TITLE, D.CREAM, 8, outline=D.INK)
    if name.startswith('SCREENIMG2') or name == 'GRAALV4SCREEN':
        img = D.panel(img, (16, 12 + top, w - 17, h - 40), alpha=160)
    if name == 'LOADINGSCREEN':
        D.centered_text(img, (0, h // 2 - 20, w, h // 2 + 20), 'Loading', D.CREAM, 4, outline=D.INK)
    foot = 'A FAN REBUILD - ART BY THE GRAAL-DELPHI PROJECT'
    D.centered_text(img, (0, h - 14, w, h - 2), foot, D.CREAM, 1)
    return img.convert('RGBA')


def draw_title(w, h):
    img = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    a = int(h * 0.7)
    D.acorn(img, a // 2 + 6, h // 2, a)
    D.centered_text(img, (a + 10, 0, w - 4, h), TITLE, D.GOLD, 8, outline=D.INK)
    return img


def piece_rects(im):
    """The pieces of a Torque bitmap array: boxes of pixels that are not
    the separator colour (the colour at 0, 0)."""
    im = im.convert('RGBA')
    w, h = im.size
    px = im.load()
    sep = px[0, 0]
    seen = [[False] * w for _ in range(h)]
    rects = []
    for y in range(h):
        for x in range(w):
            if seen[y][x] or px[x, y] == sep:
                continue
            stack = [(x, y)]
            seen[y][x] = True
            x0 = x1 = x
            y0 = y1 = y
            while stack:
                cx, cy = stack.pop()
                x0, x1, y0, y1 = min(x0, cx), max(x1, cx), min(y0, cy), max(y1, cy)
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if 0 <= nx < w and 0 <= ny < h and not seen[ny][nx] and px[nx, ny] != sep:
                        seen[ny][nx] = True
                        stack.append((nx, ny))
            rects.append((x0, y0, x1, y1))
    return sep, rects


def draw_sheet(name, w, h, sep, rects):
    img = Image.new('RGBA', (w, h), sep)
    d = ImageDraw.Draw(img)
    for i, (x0, y0, x1, y1) in enumerate(sorted(rects, key=lambda r: (r[1], r[0]))):
        pw, ph = x1 - x0 + 1, y1 - y0 + 1
        if name in ('DEFAULTCHECK', 'DEFAULTRADIO'):
            d.rectangle((x0, y0, x1, y1), fill=(0, 0, 0, 0))
            if name == 'DEFAULTRADIO':
                d.ellipse((x0, y0, x1, y1), fill=D.CREAM, outline=D.BARK)
                if i % 2:
                    d.ellipse((x0 + pw * .3, y0 + ph * .3, x1 - pw * .3, y1 - ph * .3), fill=D.FOREST)
            else:
                d.rectangle((x0, y0, x1, y1), fill=D.CREAM, outline=D.BARK)
                if i % 2:
                    d.line((x0 + 2, y0 + ph // 2, x0 + pw // 2 - 1, y1 - 2, x1 - 2, y0 + 2), fill=D.FOREST, width=2)
        elif name == 'DEFAULTTEXTEDIT':
            d.rectangle((x0, y0, x1, y1), fill=(26, 40, 30, 255))
            d.rectangle((x0, y0, x1, y1), outline=D.MOSS)
        else:
            face = (D.MOSS, D.LEAF, D.STONE, D.ACORN)[i % 4]
            sub = Image.new('RGBA', (pw, ph), (0, 0, 0, 0))
            D.bevel(sub, (0, 0, pw - 1, ph - 1), face, radius=min(3, pw // 4, ph // 4), width=1)
            if 8 <= pw <= 24 and 8 <= ph <= 24 and pw * 1.0 / ph < 1.5:
                sd = ImageDraw.Draw(sub)
                up = (i // 4) % 2 == 0
                sd.polygon([(pw * .25, ph * (.65 if up else .35)), (pw * .75, ph * (.65 if up else .35)),
                            (pw * .5, ph * (.3 if up else .7))], fill=D.INK)
            img.paste(sub, (x0, y0))
    return img


def draw_cursor(e, kind):
    w, h = e['w'], e['h']
    img = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # draw round the hot spot, kept away from the edges
    hx, hy = min(max(e['a'], 10), w - 11), min(max(e['c'], 10), h - 11)
    if kind in ('hand', 'drag', 'multidrag', 'arrow'):
        hx, hy = min(e['a'], w - 12), min(e['c'], h - 24)
        if kind == 'hand':
            hx = max(hx, 6)
    blk, wht = (0, 0, 0, 255), (255, 255, 255, 255)

    def arrow(x, y, s=1.0):
        pts = [(x, y), (x, y + 16 * s), (x + 4 * s, y + 12 * s), (x + 7 * s, y + 18 * s),
               (x + 9 * s, y + 17 * s), (x + 6 * s, y + 11 * s), (x + 11 * s, y + 11 * s)]
        d.polygon(pts, fill=wht, outline=blk)

    if kind == 'hand':
        d.rectangle((hx - 2, hy, hx + 2, hy + 12), fill=wht, outline=blk)
        d.rounded_rectangle((hx - 6, hy + 9, hx + 10, hy + 22), 4, fill=wht, outline=blk)
        for i in range(3):
            d.line((hx + 3 + i * 3, hy + 9, hx + 3 + i * 3, hy + 14), fill=blk)
    elif kind == 'wait':
        d.polygon([(hx - 7, hy - 10), (hx + 7, hy - 10), (hx, hy), (hx + 7, hy + 10), (hx - 7, hy + 10), (hx, hy)],
                  fill=wht, outline=blk)
        d.line((hx - 8, hy - 11, hx + 8, hy - 11), fill=blk, width=2)
        d.line((hx - 8, hy + 11, hx + 8, hy + 11), fill=blk, width=2)
    elif kind in ('drag', 'multidrag'):
        arrow(hx, hy)
        n = 2 if kind == 'multidrag' else 1
        for i in range(n):
            d.rectangle((hx + 8 + i * 3, hy + 16 + i * 3, hx + 16 + i * 3, hy + 24 + i * 3), fill=wht, outline=blk)
    elif kind in ('vsplit', 'hsplit'):
        v = kind == 'vsplit'
        for s in (-1, 1):
            if v:
                d.polygon([(hx, hy + s * 10), (hx - 5, hy + s * 4), (hx + 5, hy + s * 4)], fill=wht, outline=blk)
            else:
                d.polygon([(hx + s * 10, hy), (hx + s * 4, hy - 5), (hx + s * 4, hy + 5)], fill=wht, outline=blk)
        if v:
            d.rectangle((hx - 8, hy - 2, hx + 8, hy + 2), fill=blk)
        else:
            d.rectangle((hx - 2, hy - 8, hx + 2, hy + 8), fill=blk)
    elif kind == 'nodrop':
        d.ellipse((hx - 9, hy - 9, hx + 9, hy + 9), outline=blk, width=3)
        d.line((hx - 6, hy + 6, hx + 6, hy - 6), fill=blk, width=3)
    else:
        arrow(hx, hy)
    return img


def draw_icon_entry(e):
    w, h = e['w'], e['h']
    img = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    D.acorn(img, w // 2, h // 2 + max(1, h // 16), int(min(w, h) * 0.95))
    return img


# ------------------------------------------------------------------ dispatch

def is_picture(b):
    return (b[:2] in (b'BM', b'\xff\xd8') or b[:4] in (b'\x89PNG', b'\x00\x00\x01\x00', b'\x00\x00\x02\x00')
            or b[:3] == b'GIF')


def new_picture(data, hint, build, role=None):
    s = imgfmt.shape(data)
    name = base_name(hint)
    if s['fmt'] == 'ico':
        if s['kind'] == 2:
            m = re.search(r'(\d{5})$', name)
            kind = CURSORS.get(int(m.group(1)), 'arrow') if m else 'arrow'
            return imgfmt.encode_ico(s, lambda e: draw_cursor(e, kind))
        return imgfmt.encode_ico(s, draw_icon_entry)
    w, h = s['w'], s['h']
    if role is None:
        if name.startswith(SCREENS):
            role = 'screen'
        elif re.match(r'^BUTTON[1-3]$', name):
            role = 'strip'
        elif name == 'BUTTON4':
            role = 'gostrip'
        elif name == 'GRAALV4TITLE':
            role = 'title'
        elif name in ('DEFAULTCHECK', 'DEFAULTRADIO', 'DEFAULTSCROLL', 'DEFAULTTEXTEDIT'):
            role = 'sheet'
        elif name == 'OPENGLYPH':
            role = 'folder'
        else:
            role = 'leaf' if w * h <= 4096 else 'banner'
    if role == 'screen':
        img = draw_screen(name, w, h, build)
    elif role == 'strip':
        img = draw_strip(w, h)
    elif role == 'gostrip':
        img = draw_strip(w, h, 'GO')
    elif role == 'title':
        img = draw_title(w, h)
    elif role == 'sheet':
        old = Image.open(io.BytesIO(data))
        sep, rects = piece_rects(old)
        img = draw_sheet(name, w, h, sep, rects)
    elif role == 'banner':
        img = draw_banner(w, h, D.seed_of(hint))
    elif role == 'portrait':
        img = draw_portrait(w, h)
    elif role == 'portrait-full':
        img = draw_portrait(w, h, True)
    elif role == 'poses':
        img = draw_poses(w, h)
    elif role == 'thumb':
        img = D.scene(w * 4, h * 4, D.seed_of(hint), 1).resize((w, h), Image.LANCZOS).convert('RGBA')
    else:
        img = draw_glyph(role, w, h)
    if s['fmt'] == 'bmp' and s.get('key') is not None:
        # a VCL glyph's bottom-left pixel names its transparent colour:
        # keep it free, so the key stays the old file's
        img.putpixel((0, h - 1), (0, 0, 0, 0))
    return imgfmt.encode(s, img)


def new_form(data, hint, build, log):
    form = base_name(hint)

    def fn(path, prop, kind, pdata):
        if not is_picture(pdata):
            return pdata
        s = imgfmt.shape(pdata)
        f, comp = form_key(form, path)
        role = picture_role(f, comp, s.get('w', 0), s.get('h', 0))
        log.append((hint, '%s.%s' % (path, prop), role, s.get('w'), s.get('h')))
        return new_picture(pdata, '%s|%s' % (f, comp), build, role)
    return dfm.rewrite(data, fn)


def is_level(b):
    return b[:4] in (b'GR-V', b'Z3-V') or b[:8] == b'GLEVNW01'


def replacement(data, hint, build, log):
    """New bytes for one resource, or None to leave it."""
    if data[:4] == b'TPF0':
        return new_form(data, hint, build, log)
    if is_picture(data):
        try:
            imgfmt.shape(data)
        except Exception:
            return None
        log.append((hint, '', 'picture', None, None))
        return new_picture(data, hint, build)
    if is_level(data):
        log.append((hint, '', 'level', None, None))
        return levels.replace_level(data, base_name(hint))
    return None


def skip(path):
    """Whole-install packs are removed, not redrawn (see docs/art.md)."""
    return path.endswith('Install.res') or '/res/install/' in path


def run(write=True):
    changed = []
    log = []
    cache = {}
    for kind, path in C.containers():
        if skip(path):
            continue
        build = path.split('/')[0]
        blobs = C.read_blobs(kind, path)
        new = {}
        for key, hint, data in blobs:
            ck = (data, base_name(hint))
            if ck in cache:
                r = cache[ck]
            else:
                r = replacement(data, hint, build, log)
                cache[ck] = r
            if r is not None and r != data:
                new[key] = r
        if new:
            changed.append(path)
            if write:
                C.write_blobs(kind, path, new)
    return changed, log


def main():
    args = sys.argv[1:]
    if args[:1] == ['--check']:
        changed, _ = run(write=False)
        for p in changed:
            print('not our art yet:', p)
        sys.exit(1 if changed else 0)
    if args[:1] == ['--list']:
        _, log = run(write=False)
        roles = collections.Counter(r for (_, _, r, _, _) in log)
        with open(args[1], 'w') as f:
            for r, n in sorted(roles.items()):
                f.write('%s\t%d\n' % (r, n))
        return
    changed, log = run(write=True)
    print('%d containers rewritten' % len(changed))


if __name__ == '__main__':
    main()
