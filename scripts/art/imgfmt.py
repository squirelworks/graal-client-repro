"""Picture formats: read a picture's shape, write new pixels in the same shape.

`shape(data)` returns what a replacement must keep so the programs that
load it see no difference: the format, the size, the bit depth and
palette size, the transparent key, row order, icon/cursor entries and hot
spots. `encode(shape, rgba)` writes an RGBA picture back in that shape.
Only the shape is taken from the old file; the pixels are always new.
"""
import io
import struct

from PIL import Image


def _bmp_shape(b, off=0, file_header=True):
    p = off + (14 if file_header else 0)
    hsize = struct.unpack_from('<I', b, p)[0]
    if hsize == 12:
        w, h, planes, bpp = struct.unpack_from('<HHHH', b, p + 4)
        comp, clr = 0, 0
    else:
        w, h, planes, bpp, comp = struct.unpack_from('<iiHHI', b, p + 4)
        clr = struct.unpack_from('<I', b, p + 32)[0] if hsize >= 36 else 0
    top_down = h < 0
    h = abs(h)
    ncol = 0
    if bpp <= 8:
        ncol = clr or (1 << bpp)
    s = dict(fmt='bmp', w=w, h=h, bpp=bpp, comp=comp, ncol=ncol, top_down=top_down,
             hsize=hsize, file_header=file_header)
    # the transparent key of a VCL glyph is its bottom-left pixel
    try:
        im = Image.open(io.BytesIO(b[off:] if file_header else _with_file_header(b[off:])))
        im = im.convert('RGB')
        s['key'] = im.getpixel((0, im.height - 1))
    except Exception:
        s['key'] = None
    return s


def _with_file_header(dib):
    hsize = struct.unpack_from('<I', dib, 0)[0]
    bpp = struct.unpack_from('<H', dib, 14)[0] if hsize >= 16 else 8
    clr = struct.unpack_from('<I', dib, 32)[0] if hsize >= 36 else 0
    ncol = (clr or (1 << bpp)) if bpp <= 8 else 0
    off = 14 + hsize + ncol * (4 if hsize >= 40 else 3)
    return b'BM' + struct.pack('<IHHI', 14 + len(dib), 0, 0, off) + dib


def _ico_shape(b):
    kind = struct.unpack_from('<H', b, 2)[0]  # 1 icon, 2 cursor
    n = struct.unpack_from('<H', b, 4)[0]
    ents = []
    for i in range(n):
        w, h, cc, res, a, c, size, off = struct.unpack_from('<BBBBHHII', b, 6 + 16 * i)
        img = b[off:off + size]
        e = dict(w=w or 256, h=h or 256, cc=cc, a=a, c=c, dir=b[6 + 16 * i:6 + 16 * i + 8])
        if img[:4] == b'\x89PNG':
            e['png'] = True
        else:
            hs = struct.unpack_from('<I', img, 0)[0]
            e['bpp'] = struct.unpack_from('<H', img, 14)[0]
            e['hsize'] = hs
            # the DIB's own size wins: some extracted cursors carry odd
            # directory bytes, which are kept as they are
            dw, dh = struct.unpack_from('<ii', img, 4)
            e['w'], e['h'] = dw, abs(dh) // 2
        ents.append(e)
    return dict(fmt='ico', kind=kind, entries=ents, w=ents[0]['w'] if ents else 0,
                h=ents[0]['h'] if ents else 0)


def shape(data):
    if data[:2] == b'BM':
        return _bmp_shape(data)
    if data[:4] in (b'\x28\x00\x00\x00', b'\x0c\x00\x00\x00'):
        s = _bmp_shape(data, file_header=False)
        return s
    if data[:4] in (b'\x00\x00\x01\x00', b'\x00\x00\x02\x00'):
        return _ico_shape(data)
    im = Image.open(io.BytesIO(data))
    s = dict(fmt=im.format.lower(), w=im.width, h=im.height, mode=im.mode)
    if im.format == 'JPEG':
        s['progressive'] = bool(im.info.get('progressive'))
    if im.mode == 'P':
        s['ncol'] = len(im.getpalette() or []) // 3
        s['transparency'] = im.info.get('transparency')
    elif 'transparency' in im.info:
        s['transparency'] = im.info.get('transparency')
    return s


# ------------------------------------------------------------------ writers

def _quantize(rgba, n, key=None):
    """(indices image 'P', palette list of RGB) with at most n colours;
    transparent pixels take the key colour's index when there is a key."""
    rgb = Image.new('RGB', rgba.size, key or (0, 0, 0))
    rgb.paste(rgba.convert('RGB'), (0, 0), rgba)
    if key is not None:
        m = rgba.getchannel('A').point(lambda v: 255 if v >= 128 else 0)
        body = Image.new('RGB', rgba.size, (0, 0, 0))
        body.paste(rgba.convert('RGB'), (0, 0), m)
        q = body.quantize(colors=max(1, n - 1), method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
        pal = q.getpalette()[:3 * max(1, n - 1)]
        pal = [tuple(pal[i:i + 3]) for i in range(0, len(pal), 3)]
        ki = len(pal)
        # keep the key out of the body's colours
        pal = [c if c != tuple(key) else (c[0] ^ 1, c[1], c[2]) for c in pal]
        pal.append(tuple(key))
        out = Image.new('P', rgba.size)
        qd, md = q.load(), m.load()
        od = out.load()
        for y in range(rgba.height):
            for x in range(rgba.width):
                od[x, y] = qd[x, y] if md[x, y] else ki
        return out, pal
    q = rgb.quantize(colors=n, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    pal = q.getpalette()[:3 * n]
    pal = [tuple(pal[i:i + 3]) for i in range(0, len(pal), 3)]
    return q, pal


def _dib(rgba, bpp, ncol=0, top_down=False, key=None, hsize=40, ico=False):
    """A DIB (header, palette, pixels; for an icon also the AND mask)."""
    w, h = rgba.size
    rows = []
    palette = []
    if bpp <= 8:
        n = ncol or (1 << bpp)
        if ico:
            idx, palette = _quantize(rgba, n, None)
            # under the mask the colour must be black (index of 0, 0, 0),
            # or Windows inverts the screen there
            if (0, 0, 0) in palette:
                bi = palette.index((0, 0, 0))
            elif len(palette) < n:
                palette.append((0, 0, 0))
                bi = len(palette) - 1
            else:
                bi = len(palette) - 1
                palette[bi] = (0, 0, 0)
            ia = rgba.getchannel('A').load()
            ip = idx.load()
            for yy in range(h):
                for xx in range(w):
                    if ia[xx, yy] < 128:
                        ip[xx, yy] = bi
        else:
            idx, palette = _quantize(rgba, n, key)
        palette += [(0, 0, 0)] * (n - len(palette))
        px = idx.load()
        for y in range(h):
            bits = []
            for x in range(w):
                bits.append(px[x, y])
            row = bytearray()
            if bpp == 8:
                row = bytearray(bits)
            elif bpp == 4:
                for i in range(0, w, 2):
                    a = bits[i]
                    c = bits[i + 1] if i + 1 < w else 0
                    row.append((a << 4) | c)
            elif bpp == 1:
                for i in range(0, w, 8):
                    v = 0
                    for j in range(8):
                        if i + j < w and bits[i + j]:
                            v |= 0x80 >> j
                    row.append(v)
            rows.append(bytes(row))
    else:
        bg = Image.new('RGB', rgba.size, key or (0, 0, 0))
        bg.paste(rgba.convert('RGB'), (0, 0), rgba)
        src = rgba if bpp == 32 else bg
        px = src.load()
        for y in range(h):
            row = bytearray()
            for x in range(w):
                c = px[x, y]
                if bpp == 32:
                    row += bytes((c[2], c[1], c[0], c[3]))
                elif bpp == 24:
                    row += bytes((c[2], c[1], c[0]))
                elif bpp == 16:
                    v = ((c[0] >> 3) << 10) | ((c[1] >> 3) << 5) | (c[2] >> 3)
                    row += struct.pack('<H', v)
            rows.append(bytes(row))
    stride = ((w * bpp + 31) // 32) * 4
    order = rows if top_down else rows[::-1]
    pixels = b''.join(r + b'\0' * (stride - len(r)) for r in order)
    mask = b''
    if ico:
        mstride = ((w + 31) // 32) * 4
        a = rgba.getchannel('A').load()
        mrows = []
        for y in range(h):
            row = bytearray()
            for i in range(0, w, 8):
                v = 0
                for j in range(8):
                    if i + j < w and a[i + j, y] < 128:
                        v |= 0x80 >> j
                row.append(v)
            mrows.append(bytes(row) + b'\0' * (mstride - len(row)))
        mask = b''.join(mrows[::-1])
    hh = h * 2 if ico else (-h if top_down else h)
    if hsize == 12:
        hdr = struct.pack('<IHHHH', 12, w, hh, 1, bpp)
        pal = b''.join(bytes((c[2], c[1], c[0])) for c in palette)
    else:
        hdr = struct.pack('<IiiHHIIiiII', 40, w, hh, 1, bpp, 0, len(pixels) + len(mask), 0, 0,
                          len(palette) if bpp <= 8 else 0, 0)
        pal = b''.join(bytes((c[2], c[1], c[0], 0)) for c in palette)
    return hdr + pal + pixels + mask, len(hdr) + len(pal)


def encode(s, rgba):
    """New file bytes in shape s from an RGBA picture of s's size."""
    fmt = s['fmt']
    if fmt == 'bmp':
        dib, head = _dib(rgba, s['bpp'], s.get('ncol', 0), s.get('top_down', False), s.get('key'),
                         s.get('hsize', 40))
        if not s.get('file_header', True):
            return dib
        return b'BM' + struct.pack('<IHHI', 14 + len(dib), 0, 0, 14 + head) + dib
    if fmt == 'ico':
        raise ValueError('icons are written with encode_ico')
    buf = io.BytesIO()
    if fmt == 'jpeg':
        rgb = Image.new('RGB', rgba.size, (0, 0, 0))
        rgb.paste(rgba.convert('RGB'), (0, 0), rgba)
        if s.get('mode') == 'L':
            rgb = rgb.convert('L')
        rgb.save(buf, 'JPEG', quality=88, optimize=True, progressive=s.get('progressive', False))
        return buf.getvalue()
    mode = s.get('mode', 'RGBA')
    if mode == 'P' or fmt == 'gif':
        n = min(256, s.get('ncol') or 256)
        has_t = s.get('transparency') is not None
        if has_t:
            idx, pal = _quantize(rgba, n, (255, 0, 255))
            ti = len(pal) - 1
        else:
            idx, pal = _quantize(rgba, n, None)
            ti = None
        flat = []
        for c in pal:
            flat += list(c)
        idx.putpalette(flat)
        kw = {}
        if ti is not None:
            kw['transparency'] = ti
        idx.save(buf, 'GIF' if fmt == 'gif' else 'PNG', optimize=False, **kw)
        return buf.getvalue()
    if mode in ('RGB', 'L', 'LA', 'RGBA', 'I', '1'):
        if mode == 'RGB':
            out = Image.new('RGB', rgba.size, (0, 0, 0))
            out.paste(rgba.convert('RGB'), (0, 0), rgba)
        elif mode in ('L', 'I', '1'):
            out = rgba.convert('L')
        elif mode == 'LA':
            out = rgba.convert('LA')
        else:
            out = rgba
        out.save(buf, 'PNG', optimize=True)
        return buf.getvalue()
    rgba.save(buf, 'PNG', optimize=True)
    return buf.getvalue()


def encode_ico(s, draw_entry):
    """An .ico/.cur in shape s; draw_entry(entry) gives each entry's RGBA."""
    ents = s['entries']
    blobs = []
    for e in ents:
        im = draw_entry(e)
        if e.get('png'):
            buf = io.BytesIO()
            im.save(buf, 'PNG', optimize=True)
            blobs.append(buf.getvalue())
        else:
            bpp = e.get('bpp', 32)
            dib, _ = _dib(im, bpp, (1 << bpp) if bpp <= 8 else 0, False, None, 40, ico=True)
            blobs.append(dib)
    out = bytearray(struct.pack('<HHH', 0, s['kind'], len(ents)))
    off = 6 + 16 * len(ents)
    for e, b in zip(ents, blobs):
        out += e['dir'] + struct.pack('<II', len(b), off)
        off += len(b)
    for b in blobs:
        out += b
    return bytes(out)
