"""Levels: keep how a level connects, draw everything else anew.

A replacement level keeps the format (GR-V1.00 to 1.03 binary, Z3-V,
GLEVNW01 text) and the links of the level it replaces (where each edge or
door leads: that is how Training and the start level hang together), and
nothing else of it. The board is a new meadow of the project's own tiles
(common/builtin/pics1.png), with the link areas laid as path so they can
be walked to, and one sign in our own words. No NPC, script, baddy,
chest or sign text of the old level is kept.

The board codec follows Graal_analysis formats/level-binary.md (as
common/GLevel.pas reads it): 12-bit codes for GR-V1.00/1.01 and Z3-V,
13-bit for GR-V1.02/1.03, a code with the top bit set gives a repeat
count (bit 8: a repeated pair).
"""
import draw

BOARD = 64 * 64
SIGN_CHARS = ('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
              '!?-.,#>()#####"####\':/~&### <####;\n')
NW_ALPHA = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'


def code_width(magic):
    return 13 if magic in ('GR-V1.02', 'GR-V1.03') else 12


def read_grv_links(data):
    magic = data[:8].decode('latin1')
    width = code_width(magic)
    flag = 1 << (width - 1)
    p, buf, nbits, n = 8, 0, 0, 0
    count, double, have_first = 1, False, False
    while n < BOARD:
        while nbits < width:
            if p >= len(data):
                return magic, []
            buf |= data[p] << nbits
            p += 1
            nbits += 8
        code = buf & ((1 << width) - 1)
        buf >>= width
        nbits -= width
        if code & flag:
            count = code & 0xFF
            double = bool(code & 0x100)
            continue
        if count == 1:
            n += 1
        elif not double:
            n += count
            count = 1
        elif not have_first:
            have_first = True
        else:
            n += 2 * count
            have_first, count, double = False, 1, False
    links = []
    rest = data[p:].decode('latin1')
    for line in rest.split('\n'):
        if line in ('', '#'):
            break
        parts = line.split()
        if len(parts) < 7:
            continue
        links.append((' '.join(parts[:-6]),) + tuple(parts[-6:]))
    return magic, links


def read_nw_links(data):
    links = []
    for line in data.decode('latin1').splitlines():
        if line.startswith('LINK '):
            parts = line.split()[1:]
            if len(parts) >= 7:
                links.append((' '.join(parts[:-6]),) + tuple(parts[-6:]))
    return links


def write_board(tiles, width):
    flag = 1 << (width - 1)
    codes = []
    i = 0
    while i < BOARD:
        t = tiles[i]
        if i < BOARD - 3 and tiles[i + 1] == t:
            n = 2
            i += 2
            while n < 64 and i < BOARD and tiles[i] == t:
                n += 1
                i += 1
            codes += [flag | n, t]
        else:
            codes.append(t)
            i += 1
    out = bytearray()
    acc = nacc = 0
    for c in codes:
        acc |= (c & ((1 << width) - 1)) << nacc
        nacc += width
        while nacc >= 8:
            out.append(acc & 0xFF)
            acc >>= 8
            nacc -= 8
    if nacc:
        out.append(acc & 0xFF)
    return bytes(out)


def encode_sign(text):
    out = bytearray()
    for ch in text:
        k = SIGN_CHARS.find(ch)
        if k < 0 or ch == '#':
            k = SIGN_CHARS.find(' ')
        out.append(k + 32)
    return bytes(out)


def _int(v, default):
    try:
        return int(float(v))
    except ValueError:
        return default


def board_for(name, links):
    """A 64 x 64 meadow; each link's area and the way to it are path."""
    a = draw.landscape(draw.seed_of(name), 64, 64)
    for (_, x, y, w, h, _, _) in links:
        x, y, w, h = _int(x, 0), _int(y, 0), _int(w, 1), _int(h, 1)
        cx, cy = min(63, max(0, x + w // 2)), min(63, max(0, y + h // 2))
        for yy in range(max(0, y), min(64, y + h)):
            for xx in range(max(0, x), min(64, x + w)):
                a[xx + yy * 64] = draw.T_PATH
        # a path from the middle to the link
        mx, my = 32, 32
        for xx in range(min(cx, mx), max(cx, mx) + 1):
            a[xx + my * 64] = draw.T_PATH
        for yy in range(min(cy, my), max(cy, my) + 1):
            a[cx + yy * 64] = draw.T_PATH
    for (x, y) in ((29, 29), (30, 29)):
        a[x + y * 64] = draw.O_SIGN + (x - 29)
        a[x + (y + 1) * 64] = draw.O_SIGN + 16 + (x - 29)
    return a


SIGN_TEXT = ('A meadow drawn for graal-delphi.\n'
             'Put your own Graal files in assets/\n'
             'to see the original level here.')


def replace_level(data, name):
    if data[:8] == b'GLEVNW01':
        links = read_nw_links(data)
        a = board_for(name, links)
        lines = ['GLEVNW01']
        for y in range(64):
            row = ''.join(NW_ALPHA[t >> 6] + NW_ALPHA[t & 63] for t in a[y * 64:(y + 1) * 64])
            lines.append('BOARD 0 %d 64 0 %s' % (y, row))
        for l in links:
            lines.append('LINK %s %s %s %s %s %s %s' % l)
        lines.append('SIGN 29 29')
        lines += SIGN_TEXT.split('\n')
        lines.append('SIGNEND')
        nl = '\r\n' if b'\r\n' in data[:200] else '\n'
        return (nl.join(lines) + nl).encode('latin1')
    magic, links = read_grv_links(data)
    a = board_for(name, links)
    out = bytearray(magic.encode('latin1'))
    out += write_board(a, code_width(magic))
    for l in links:
        out += ('%s %s %s %s %s %s %s\n' % l).encode('latin1')
    out += b'#\n'
    out += b'\xff\xff\xff\n'           # no baddies
    if magic.startswith('GR-'):
        out += b'#\n'                   # no NPCs
    if magic in ('GR-V1.01', 'GR-V1.02', 'GR-V1.03'):
        out += b'#\n'                   # no chests
    out += bytes((29 + 32, 29 + 32)) + encode_sign(SIGN_TEXT) + b'\n'
    return bytes(out)
