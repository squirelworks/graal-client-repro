"""A Delphi binary form (TPF0) as text, the way Delphi shows a .dfm.
Binary properties (pictures) are shown by size only."""
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


def _val(r):
    t = r.u8()
    if t == 0:
        return 'null'
    if t == 1:
        items = []
        while r.b[r.p] != 0:
            items.append(_val(r))
        r.p += 1
        return '(' + ' '.join(items) + ')'
    if t == 2:
        return str(struct.unpack('<b', r.n(1))[0])
    if t == 3:
        return str(struct.unpack('<h', r.n(2))[0])
    if t == 4:
        return str(struct.unpack('<i', r.n(4))[0])
    if t == 5:
        return '%g' % _ext(r.n(10))
    if t in (6, 7):
        s = r.ss()
        return s if t == 7 else repr(s)
    if t == 8:
        return 'False'
    if t == 9:
        return 'True'
    if t == 10:
        ln = struct.unpack('<i', r.n(4))[0]
        r.n(ln)
        return '{binary, %d bytes}' % ln
    if t == 11:
        s = []
        while True:
            x = r.ss()
            if not x:
                break
            s.append(x)
        return '[' + ', '.join(s) + ']'
    if t == 12:
        ln = struct.unpack('<i', r.n(4))[0]
        return repr(r.n(ln).decode('latin1'))
    if t == 13:
        return 'nil'
    if t == 14:
        items = []
        while r.b[r.p] != 0:
            props = []
            while r.b[r.p] != 0:
                pn = r.ss()
                props.append(pn + ' = ' + _val(r))
            r.p += 1
            items.append('item ' + '; '.join(props) + ' end')
        r.p += 1
        return '<' + ' '.join(items) + '>'
    if t == 18:
        ln = struct.unpack('<i', r.n(4))[0]
        return repr(r.n(ln * 2).decode('utf-16le'))
    if t == 19:
        return str(struct.unpack('<q', r.n(8))[0])
    raise ValueError('value type %d at %d' % (t, r.p))


def _ext(b):
    mant = int.from_bytes(b[:8], 'little')
    se = int.from_bytes(b[8:10], 'little')
    if mant == 0:
        return 0.0
    return (-1) ** (se >> 15) * mant / (1 << 63) * 2.0 ** ((se & 0x7FFF) - 16383)


def _obj(r, ind, out):
    f = r.b[r.p]
    if f & 0xF0 == 0xF0:
        r.p += 1
        if f & 2:
            _val(r)
    cls = r.ss()
    name = r.ss()
    out.append(' ' * ind + 'object %s: %s' % (name, cls))
    while r.b[r.p] != 0:
        pn = r.ss()
        out.append(' ' * (ind + 2) + pn + ' = ' + _val(r))
    r.p += 1
    while r.b[r.p] != 0:
        _obj(r, ind + 2, out)
    r.p += 1
    out.append(' ' * ind + 'end')


def dfm_to_text(data):
    r = _R(data)
    if r.n(4) != b'TPF0':
        raise ValueError('not a TPF0 form')
    out = []
    _obj(r, 0, out)
    return '\n'.join(out) + '\n'
