"""The asset pack of the Graal Game Boy Color rebuild, and the tool that puts
one into a built ROM.

The engine (banks 0 to 3) never holds graphics or rooms. They live in an
asset pack in banks 8 to 15, which the engine reads through a directory at
the start of bank 8. make_builtin.py writes a pack of this project's own
stand-in art; import_assets.py writes one from a ROM the player owns. Both
use this module, so the two packs always have the same shape.

Pack layout (bank 8, address $4000):
  'GPAK', version, item count, then 5 bytes per item: bank, address (LE),
  length (LE). An item that is not there has bank 0.
No item crosses a bank boundary.

Usage:
  python3 -I gpak.py patch ENGINE.gbc PACK.bin OUT.gbc
Standard library only.
"""
import struct
import sys

PACK_FIRST_BANK = 8
PACK_LAST_BANK = 15
BANK_SIZE = 0x4000
VERSION = 1

# item ids, the same numbers as src/pak.h
TILES0, TILES1, FONT, WALK, BGPAL, ANIM, SPRITES, CHARS, HEADS, LIFT, START, \
    SWORDPAL, OBJPAL = range(13)
ROOM0 = 16
NUM_ROOMS = 7
NUM_ITEMS = ROOM0 + NUM_ROOMS

NUM_CHARS = 31
CHAR_REC = 48          # name[18], palette 24 bytes, head, sword colour, A item, 3 spare
NAME_LEN = 18

# A items, chosen per character
A_NONE, A_LIFT, A_BOMB, A_BOOMERANG = range(4)

# text codes: the game's own alphabet (space, A-Z, a-z, 0-9, punctuation)
_PUNCT = "!?:.,-()'/+*=%"     # codes $5F to $6C; font tiles $4D-$51 are the window's


def text_code(ch):
    if ch == ' ':
        return 0x20
    if 'A' <= ch <= 'Z':
        return 0x21 + ord(ch) - ord('A')
    if 'a' <= ch <= 'z':
        return 0x3B + ord(ch) - ord('a')
    if '0' <= ch <= '9':
        return 0x55 + ord(ch) - ord('0')
    if ch == '"':
        return 0x67
    i = _PUNCT.find(ch)
    if i < 0:
        raise ValueError('no text code for %r' % ch)
    return 0x5F + i


def encode_text(s):
    return bytes(text_code(c) for c in s)


# the glyph each code shows, for drawing a font
def code_chars():
    out = {}
    for c in [' '] + [chr(i) for i in range(65, 91)] + [chr(i) for i in range(97, 123)] + \
            [chr(i) for i in range(48, 58)] + list(_PUNCT):
        out[text_code(c)] = c
    return out


def cgb_color(r, g, b):
    """8-bit RGB to a CGB 15-bit colour."""
    return (r >> 3) | (g >> 3) << 5 | (b >> 3) << 10


def palette(colors):
    """Four (r, g, b) to 8 bytes."""
    return b''.join(struct.pack('<H', cgb_color(*c)) for c in colors)


def room_blob(tileset, palset, tiles, attrs, links, texts, npcs):
    """tiles, attrs: 1024 bytes each. links: (x, y, w, h, newx, newy, room).
    texts: (x, y, bytes). npcs: 16-byte records."""
    assert len(tiles) == 1024 and len(attrs) == 1024
    head = bytes([tileset, palset, len(links), len(texts), len(npcs)])
    body = bytearray(head + bytes(tiles) + bytes(attrs))
    for (x, y, w, h, nx, ny, room) in links:
        body += bytes([x & 255, y & 255, w, h, nx & 255, ny & 255]) + struct.pack('<H', room)
    text_table = len(body)
    body += bytes(4 * len(texts))
    for n, rec in enumerate(npcs):
        assert len(rec) == 16, n
        body += rec
    for i, (x, y, s) in enumerate(texts):
        off = len(body)
        body[text_table + 4 * i: text_table + 4 * i + 4] = bytes([x & 255, y & 255]) + struct.pack('<H', off)
        body += bytes(s) + b'\0'
    return bytes(body)


def build_pack(items):
    """items: {id: bytes}. Returns the pack as one bytes object covering
    banks 8 to 15 (its length is a multiple of 16 KB)."""
    banks = [bytearray()]
    dir_len = 6 + 5 * NUM_ITEMS
    banks[0] += bytes(dir_len)
    where = {}
    for i in sorted(items):
        data = items[i]
        if len(data) > BANK_SIZE:
            raise ValueError('item %d is larger than a bank' % i)
        if len(banks[-1]) + len(data) > BANK_SIZE:
            banks.append(bytearray())
        where[i] = (PACK_FIRST_BANK + len(banks) - 1, 0x4000 + len(banks[-1]))
        banks[-1] += data
    if PACK_FIRST_BANK + len(banks) - 1 > PACK_LAST_BANK:
        raise ValueError('the pack does not fit in banks %d to %d' % (PACK_FIRST_BANK, PACK_LAST_BANK))
    d = bytearray(b'GPAK' + bytes([VERSION, NUM_ITEMS]))
    for i in range(NUM_ITEMS):
        b, a = where.get(i, (0, 0))
        d += bytes([b]) + struct.pack('<HH', a, len(items[i]) if i in items else 0)
    banks[0][:dir_len] = d
    out = bytearray()
    for b in banks:
        out += b + b'\xff' * (BANK_SIZE - len(b))
    return bytes(out)


def read_pack(rom):
    """The items of the pack in a built ROM, as {id: bytes}."""
    base = PACK_FIRST_BANK * BANK_SIZE
    if rom[base:base + 4] != b'GPAK':
        raise ValueError('the ROM holds no asset pack')
    items = {}
    for i in range(rom[base + 5]):
        b, a, n = struct.unpack('<BHH', rom[base + 6 + 5 * i: base + 11 + 5 * i])
        if b:
            o = b * BANK_SIZE + a - 0x4000
            items[i] = bytes(rom[o:o + n])
    return items


def fix_checksums(rom):
    c = 0
    for i in range(0x134, 0x14D):
        c = (c - rom[i] - 1) & 0xFF
    rom[0x14D] = c
    g = (sum(rom) - rom[0x14E] - rom[0x14F]) & 0xFFFF
    rom[0x14E] = g >> 8
    rom[0x14F] = g & 0xFF


def patch(engine, pack):
    """engine: the linked ROM (bytes). Returns a 256 KB ROM with the pack in
    banks 8 to 15."""
    rom = bytearray(engine)
    size = (PACK_LAST_BANK + 1) * BANK_SIZE
    if len(rom) < size:
        rom += b'\xff' * (size - len(rom))
    base = PACK_FIRST_BANK * BANK_SIZE
    for i in range(base, size):
        if rom[i] != 0xFF:
            raise ValueError('the engine uses bank %d, which belongs to the pack' % (i // BANK_SIZE))
    rom[base:base + len(pack)] = pack
    rom[0x148] = 0x03            # ROM size: 256 KB, 16 banks
    fix_checksums(rom)
    return bytes(rom)


def main(argv):
    if len(argv) != 5 or argv[1] != 'patch':
        print(__doc__)
        return 2
    with open(argv[2], 'rb') as f:
        engine = f.read()
    with open(argv[3], 'rb') as f:
        pack = f.read()
    with open(argv[4], 'wb') as f:
        f.write(patch(engine, pack))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
