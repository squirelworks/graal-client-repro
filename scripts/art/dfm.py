"""Delphi binary forms (TPF0): find the pictures inside and swap them.

A form is a tree of objects, each with properties. Pictures are binary
properties (value type 10): Picture.Data, Glyph.Data, Icon.Data,
Bitmap.Data and the like. Picture.Data starts with the graphic's class
name (TBitmap, TJPEGImage, TIcon, ...); for TBitmap and TJPEGImage a
4-byte size follows, then the file (BMP or JPEG); TIcon carries the .ico
file directly. Glyph.Data and Bitmap.Data are a 4-byte size and a BMP.

`rewrite(form, fn)` calls fn(owner_path, prop, kind, data) for each picture
and puts back what it returns, rebuilding the length fields. Everything
else in the form is copied byte for byte.
"""
import struct


class _R:
    def __init__(self, b):
        self.b, self.p = b, 0

    def u8(self):
        v = self.b[self.p]
        self.p += 1
        return v

    def n(self, k):
        v = self.b[self.p:self.p + k]
        self.p += k
        return v

    def ss(self):
        return self.n(self.u8()).decode('latin1')


def _skip_val(r):
    """Skips one value; returns (type, start, end) of its payload."""
    t = r.u8()
    s = r.p
    if t in (0, 8, 9, 13):
        pass
    elif t == 1:
        while r.b[r.p] != 0:
            _skip_val(r)
        r.p += 1
    elif t == 2:
        r.p += 1
    elif t == 3:
        r.p += 2
    elif t == 4:
        r.p += 4
    elif t == 5:
        r.p += 10
    elif t in (6, 7):
        r.p += 1 + r.b[r.p]
    elif t in (10, 12):
        r.p += 4 + struct.unpack_from('<i', r.b, r.p)[0]
    elif t == 11:
        while True:
            ln = r.u8()
            if ln == 0:
                break
            r.p += ln
    elif t == 14:
        # each item: an optional order (an integer value), a list of
        # properties (vaList ... 0)
        while r.b[r.p] != 0:
            if r.b[r.p] in (2, 3, 4):
                _skip_val(r)
            if r.b[r.p] != 1:
                raise ValueError('collection item at %d' % r.p)
            r.p += 1
            while r.b[r.p] != 0:
                r.ss()
                _skip_val(r)
            r.p += 1
        r.p += 1
    elif t == 15:  # single
        r.p += 4
    elif t == 16:  # currency
        r.p += 8
    elif t == 17:  # date
        r.p += 8
    elif t == 18:
        r.p += 4 + 2 * struct.unpack_from('<i', r.b, r.p)[0]
    elif t == 19:
        r.p += 8
    elif t == 20:  # utf8 string
        r.p += 4 + struct.unpack_from('<i', r.b, r.p)[0]
    else:
        raise ValueError('value type %d at %d' % (t, r.p - 1))
    return t, s, r.p


PICTURE_PROPS = ('Picture.Data', 'Glyph.Data', 'Bitmap.Data', 'Icon.Data')


def _split_picture(prop, payload):
    """(kind, prefix, data, suffix) of a binary property's payload; kind
    None for binary data that is not a picture (Effects, Keyboard, Items:
    other components' own data)."""
    if not prop.endswith(PICTURE_PROPS):
        return None, b'', payload, b''
    if prop.endswith('Picture.Data') or prop.endswith('.Picture.Data'):
        cls = payload[1:1 + payload[0]].decode('latin1')
        rest = payload[1 + payload[0]:]
        if cls in ('TBitmap', 'TJPEGImage', 'TGIFImage', 'TPNGObject', 'TPngImage'):
            size = struct.unpack_from('<i', rest, 0)[0]
            if 0 < size <= len(rest) - 4:
                return cls, payload[:1 + payload[0]], rest[4:4 + size], rest[4 + size:]
        return cls, payload[:1 + payload[0]], rest, b''
    if len(payload) >= 4:
        size = struct.unpack_from('<i', payload, 0)[0]
        if 0 < size <= len(payload) - 4:
            return 'raw', b'', payload[4:4 + size], payload[4 + size:]
    return None, b'', payload, b''


def _join_picture(kind, prefix, data, suffix):
    if kind is None:
        return data
    if kind in ('TBitmap', 'TJPEGImage', 'TGIFImage', 'TPNGObject', 'TPngImage') or kind == 'raw':
        if kind == 'raw' and not prefix:
            return struct.pack('<i', len(data)) + data + suffix
        return prefix + struct.pack('<i', len(data)) + data + suffix
    return prefix + data + suffix


def pictures(form):
    """[(path, prop, kind, data)] of the pictures in a form."""
    out = []
    rewrite(form, lambda path, prop, kind, data: out.append((path, prop, kind, data)) or data)
    return out


def rewrite(form, fn):
    if form[:4] != b'TPF0':
        raise ValueError('not a TPF0 form')
    r = _R(form)
    r.p = 4
    out = bytearray(b'TPF0')

    def obj(path):
        s = r.p
        f = r.b[r.p]
        if f & 0xF0 == 0xF0:
            r.p += 1
            if f & 2:
                _skip_val(r)
        r.ss()
        name = r.ss()
        out.extend(r.b[s:r.p])
        here = path + [name]
        while r.b[r.p] != 0:
            ps = r.p
            prop = r.ss()
            vs = r.p
            t, a, e = _skip_val(r)
            if t == 10:
                ln = struct.unpack_from('<i', r.b, a)[0]
                payload = r.b[a + 4:a + 4 + ln]
                kind, prefix, data, suffix = _split_picture(prop, payload)
                new = fn('.'.join(here), prop, kind, data) if kind else data
                if new is None:
                    new = data
                newp = _join_picture(kind, prefix, new, suffix)
                out.extend(r.b[ps:vs])
                out.append(10)
                out.extend(struct.pack('<i', len(newp)))
                out.extend(newp)
            else:
                out.extend(r.b[ps:e])
        out.append(0)
        r.p += 1
        while r.b[r.p] != 0:
            obj(here)
        out.append(0)
        r.p += 1

    obj([])
    out.extend(r.b[r.p:])
    return bytes(out)
