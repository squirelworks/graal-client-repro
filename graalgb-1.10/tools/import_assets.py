"""Makes a Graal Game Boy Color rebuild ROM that shows the original demo's
own graphics, palettes, rooms and texts, read from a copy of the demo that
you own.

The rebuild's engine holds no assets; it reads them from an asset pack in
banks 8 to 15. This tool reads your copy of the demo, writes a pack from
it, and puts that pack into the rebuild (GraalGB.gbc) in place of the
stand-in one. Nothing from the demo is in this tool or in this project.

Where it looks for the demo, first match wins (a file whose MD5 is the
demo's, whatever its name, among *.gb and *.gbc files):
  --data DIR, if given
  the folder this tool is in, and the folder GraalGB.gbc is in
  graal-assets/gb-1.10/ and graal-assets/common/ inside those folders

Usage:
  python3 -I import_assets.py [--data DIR] [--rom GraalGB.gbc] [--out FILE]
Writes GraalGB-original.gbc next to GraalGB.gbc unless --out says otherwise.
Standard library only.
"""
import hashlib
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gpak  # noqa: E402

DEMO_MD5 = '2b2fef91df11f9fbae3e1ece2366fdd3'   # Graal Adventure Demo v1.1 (CGB), 262,144 bytes
VERSION_DIR = 'gb-1.10'

FONT_TILES = 82
NUM_HEADS = 20
NUM_BG_SETS = 5

# What the demo did, seen in an emulator (graal_analysis
# client-internals/gameboy-demo.md): the start, the A items, sword colours.
START = bytes([0, 0x00, 0x01, 0x00, 0x01, 2, 0])   # room 0, (256, 256), facing down, character 0
A_ITEM = {0: gpak.A_LIFT, 2: gpak.A_BOMB, 7: gpak.A_BOOMERANG}
SWORD_COLOUR = {1: 1, 17: 1, 6: 2}
# The look of each liftable kind when carried (this rebuild's own object
# sprites): bush, bush, stone post, rock.
LIFT_LOOK = (0, 0, 2, 1)


class Rom:
    def __init__(self, data):
        self.d = data

    def off(self, bank, addr):
        return addr if bank == 0 else bank * 0x4000 + (addr - 0x4000)

    def bytes(self, bank, addr, n):
        o = self.off(bank, addr)
        return self.d[o:o + n]

    def word(self, bank, addr):
        b = self.bytes(bank, addr, 2)
        return b[0] | b[1] << 8

    def cstr(self, bank, addr, limit=512):
        o = self.off(bank, addr)
        e = self.d.index(b'\0', o, o + limit)
        return self.d[o:e]


def ascii_to_codes(s):
    out = bytearray()
    for c in s.decode('latin-1'):
        try:
            out.append(gpak.text_code(c))
        except ValueError:
            out.append(0x20)
    return bytes(out)


# ---------------------------------------------------------------- finding the data
# The demo's tables are found by their shape, not by where they sit, so this
# tool carries no addresses of the demo. Each search checks its result
# against what must hold for that table and stops if it is not found once.

BANK = 0x4000


def bank_addr(off):
    """A file offset as (bank, CPU address)."""
    b = off // BANK
    return b, (off % BANK) + (BANK if b else 0)


def file_off(bank, addr):
    return addr if bank == 0 else bank * BANK + (addr - BANK)


def tile_colours(t):
    cols = set()
    for y in range(8):
        lo, hi = t[2 * y], t[2 * y + 1]
        for x in range(8):
            cols.add((lo >> x & 1) | (hi >> x & 1) << 1)
    return cols


class Layout:
    """Where each table is, found in a copy of the demo."""

    def __init__(self, d):
        self.d = d
        self.find_font_block()
        self.find_characters()
        self.find_rooms()
        self.find_lift_tables()

    def word(self, off):
        return self.d[off] | self.d[off + 1] << 8

    def only(self, found, what):
        if len(found) != 1:
            raise SystemExit('Could not find %s in this copy of the demo (%d matches).' % (what, len(found)))
        return found[0]

    def find_font_block(self):
        """The font: a blank tile (all colour 1), then glyphs in colours 1 and 3,
        ending with three frame tiles that also use colour 2. In the same
        bank, right after it: walk bits (2 x 32 bytes), a second bit set of
        the same size, five BG palette sets (5 x 64) and a table of five
        pointers to those sets."""
        d, found = self.d, []
        blank = b'\xff\x00' * 8
        i = d.find(blank)
        while i >= 0:
            f = i
            tiles = [d[f + 16 * k: f + 16 * k + 16] for k in range(FONT_TILES)]
            if (len(tiles[-1]) == 16 and
                    all(tile_colours(t) == {1, 3} for t in tiles[1:0x4D]) and
                    all(2 in tile_colours(t) for t in tiles[0x4F:0x52])):
                pal = f + FONT_TILES * 16 + 128
                ptrs = pal + NUM_BG_SETS * 64
                b, pa = bank_addr(pal)
                if all(self.word(ptrs + 2 * k) == pa + 64 * k for k in range(NUM_BG_SETS)):
                    found.append(f)
            i = d.find(blank, i + 1)
        self.font = self.only(found, 'the font')
        self.walk = self.font + FONT_TILES * 16
        self.palettes = self.walk + 128
        self.font_bank, font_addr = bank_addr(self.font)
        # the two tile sets: a pair of pointers, 4 KB apart, to the 8 KB just
        # before the font; the animated tiles follow that pair
        bank_start = self.font_bank * BANK
        pairs = []
        for o in range(bank_start, bank_start + BANK - 4):
            w0, w1 = self.word(o), self.word(o + 2)
            if w0 + 0x1000 == w1 and w1 + 0x1000 == font_addr:
                pairs.append(o)
        tp = self.only(pairs, 'the tile set pointers')
        self.tilesets = (file_off(self.font_bank, self.word(tp)), file_off(self.font_bank, self.word(tp + 2)))
        self.anim0 = tp + 4               # 4 frames of tile 3 (tile set 0)
        self.anim1 = self.anim0 + 64      # 4 frames of tiles $26-$27 (tile set 1)
        self.anim0b = self.anim1 + 128    # 2 frames of tile $fb (tile set 0)

    def find_characters(self):
        """31 records of three pointers (name, three OBJ palettes, head) in one
        bank; every name a short line of letters and spaces, every head a
        whole number of 128-byte heads from the first."""
        d, found = self.d, []

        def name_ok(off):
            e = d.find(b'\0', off, off + 20)
            if e < 0 or e - off < 2:
                return False
            return all(c == 0x20 or 0x41 <= c <= 0x5A or 0x61 <= c <= 0x7A for c in d[off:e])

        for b in range(1, len(d) // BANK):
            start = b * BANK
            for o in range(start, start + BANK - 6 * gpak.NUM_CHARS):
                recs = [(self.word(o + 6 * k), self.word(o + 6 * k + 2), self.word(o + 6 * k + 4))
                        for k in range(gpak.NUM_CHARS)]
                if not all(BANK <= p < 2 * BANK for r in recs for p in r):
                    continue
                if not all(name_ok(file_off(b, r[0])) for r in recs):
                    continue
                heads = [r[2] for r in recs]
                h0 = min(heads)
                if any((h - h0) % 128 for h in heads):
                    continue
                found.append((b, o, h0, recs))
        b, o, h0, recs = self.only(found, 'the character table')
        self.char_bank, self.char_recs = b, recs
        self.heads = file_off(b, h0)
        self.num_heads = (max(r[2] for r in recs) - h0) // 128 + 1

    def room_header(self, bank, addr):
        """A room header, if a valid one sits there."""
        if not BANK <= addr < 2 * BANK - 13:
            return None
        h = self.d[file_off(bank, addr): file_off(bank, addr) + 13]
        mp = h[0] | h[1] << 8
        ptrs = [(h[5] | h[6] << 8, h[4], 8), (h[8] | h[9] << 8, h[7], 4), (h[11] | h[12] << 8, h[10], 16)]
        if not (BANK <= mp <= 2 * BANK - 2048 and h[2] in (0, 1) and h[3] < NUM_BG_SETS and 1 <= h[4] <= 8):
            return None
        for p, n, size in ptrs:
            if n > 8 or (n and not BANK <= p <= 2 * BANK - n * size):
                return None
        return h

    def find_rooms(self):
        """A table of seven pointers to room headers (in its own bank or the
        next) whose links all lead to one of the seven rooms."""
        d, found = self.d, []
        for b in range(1, len(d) // BANK - 1):
            start = b * BANK
            for o in range(start, start + BANK - 14, 2):
                rooms = []
                for r in range(gpak.NUM_ROOMS):
                    addr = self.word(o + 2 * r)
                    for rb in (b, b + 1):
                        h = self.room_header(rb, addr)
                        if h is not None:
                            lp = file_off(rb, h[5] | h[6] << 8)
                            if all(d[lp + 8 * i + 6] < gpak.NUM_ROOMS and d[lp + 8 * i + 7] == 0 for i in range(h[4])):
                                rooms.append((rb, addr, h))
                                break
                    else:
                        break
                if len(rooms) == gpak.NUM_ROOMS:
                    found.append(rooms)
        self.rooms = self.only(found, 'the room table')

    def find_lift_tables(self):
        """The liftable objects: four (top-left, top-right) tile pairs, four
        spare bytes, then the 2x2 tiles each kind leaves behind, the last
        kind's all $ff (it puts the room's own tiles back). The first three
        kinds' pairs all stand side by side somewhere in the rooms."""
        d = self.d
        pairs = set()
        for rb, addr, h in self.rooms:
            m = d[file_off(rb, h[0] | h[1] << 8): file_off(rb, h[0] | h[1] << 8) + 1024]
            for y in range(32):
                for x in range(31):
                    pairs.add((m[y * 32 + x], m[y * 32 + x + 1]))
        found = []
        i = d.find(b'\xff' * 4)
        while i >= 0:
            o = i - 24
            if o >= 0 and d[o + 28: o + 29] != b'\xff':
                w = d[o:o + 28]
                kinds = [(w[2 * k], w[2 * k + 1]) for k in range(4)]
                if (all(k in pairs for k in kinds[:3]) and len(set(kinds[:3])) == 3 and
                        all(t != 0xFF for t in w[12:24])):
                    found.append(o)
            i = d.find(b'\xff' * 4, i + 1)
        self.lift = self.only(found, 'the liftable objects')


def demo_items(data, builtin):
    L = Layout(data)
    d = data
    items = dict(builtin)
    items[gpak.TILES0] = d[L.tilesets[0]:L.tilesets[0] + 4096]
    items[gpak.TILES1] = d[L.tilesets[1]:L.tilesets[1] + 4096]
    # the demo's font, window frame and arrows; capitals use BG palette 1
    items[gpak.FONT] = bytes([FONT_TILES, 1]) + d[L.font:L.font + FONT_TILES * 16]
    items[gpak.WALK] = d[L.walk:L.walk + 64]
    items[gpak.BGPAL] = bytes([NUM_BG_SETS]) + d[L.palettes:L.palettes + NUM_BG_SETS * 64]
    a0, a1, a0b = d[L.anim0:L.anim0 + 64], d[L.anim1:L.anim1 + 128], d[L.anim0b:L.anim0b + 32]
    anim = bytearray([2, 3, 4]) + a0
    anim += bytes([0xFB, 2]) + a0b
    anim += bytes([2, 0x26, 4]) + b''.join(a1[f * 32:f * 32 + 16] for f in range(4))
    anim += bytes([0x27, 4]) + b''.join(a1[f * 32 + 16:f * 32 + 32] for f in range(4))
    items[gpak.ANIM] = bytes(anim)
    items[gpak.HEADS] = bytes([L.num_heads]) + d[L.heads:L.heads + L.num_heads * 128]
    chars = bytearray([gpak.NUM_CHARS])
    head0 = bank_addr(L.heads)[1]
    for k, (np_, pp, hp) in enumerate(L.char_recs):
        no = file_off(L.char_bank, np_)
        name = ascii_to_codes(d[no:d.index(b'\0', no)])[:gpak.NAME_LEN]
        rec = bytearray(name + bytes(gpak.NAME_LEN - len(name)))
        po = file_off(L.char_bank, pp)
        rec += d[po:po + 24]
        rec += bytes([(hp - head0) // 128, SWORD_COLOUR.get(k, 0), A_ITEM.get(k, gpak.A_NONE), 0, 0, 0])
        chars += rec
    items[gpak.CHARS] = bytes(chars)
    lt = d[L.lift:L.lift + 8]
    lifted = d[L.lift + 12:L.lift + 28]
    items[gpak.LIFT] = bytes(lt[0::2]) + bytes(lt[1::2]) + lifted + bytes(LIFT_LOOK)
    items[gpak.START] = START
    rom = Rom(d)
    for r, (bank, _, hdr) in enumerate(L.rooms):
        mp = hdr[0] | hdr[1] << 8
        m = rom.bytes(bank, mp, 2048)
        nl, lp = hdr[4], hdr[5] | hdr[6] << 8
        nt, tp = hdr[7], hdr[8] | hdr[9] << 8
        nn, npp = hdr[10], hdr[11] | hdr[12] << 8
        links = []
        for i in range(nl):
            x, y, w, h, nx, ny, rlo, rhi = rom.bytes(bank, lp + 8 * i, 8)
            links.append((x, y, w, h, nx, ny, rlo | rhi << 8))
        texts = []
        for i in range(nt):
            x, y, slo, shi = rom.bytes(bank, tp + 4 * i, 4)
            texts.append((x, y, rom.cstr(bank, slo | shi << 8)))
        npcs = [rom.bytes(bank, npp + 16 * i, 16) for i in range(nn)]
        items[gpak.ROOM0 + r] = gpak.room_blob(hdr[2], hdr[3], m[:1024], m[1024:], links, texts, npcs)
    return items


def find_demo(dirs):
    for d in dirs:
        for sub in ('', os.path.join('graal-assets', VERSION_DIR), os.path.join('graal-assets', 'common')):
            p = os.path.join(d, sub)
            if not os.path.isdir(p):
                continue
            for name in sorted(os.listdir(p)):
                if not name.lower().endswith(('.gb', '.gbc')):
                    continue
                f = os.path.join(p, name)
                if os.path.getsize(f) != 262144:
                    continue
                with open(f, 'rb') as fh:
                    data = fh.read()
                if hashlib.md5(data).hexdigest() == DEMO_MD5:
                    return f, data
    return None, None


def main(argv):
    args = argv[1:]
    data_dir = rom_path = out = None
    while args:
        a = args.pop(0)
        if a == '--data' and args:
            data_dir = args.pop(0)
        elif a == '--rom' and args:
            rom_path = args.pop(0)
        elif a == '--out' and args:
            out = args.pop(0)
        else:
            print(__doc__)
            return 2
    if rom_path is None:
        for d in (HERE, os.path.dirname(HERE), os.getcwd()):
            if os.path.isfile(os.path.join(d, 'GraalGB.gbc')):
                rom_path = os.path.join(d, 'GraalGB.gbc')
                break
    if rom_path is None or not os.path.isfile(rom_path):
        print('GraalGB.gbc not found; give it with --rom')
        return 1
    with open(rom_path, 'rb') as f:
        engine = f.read()
    dirs = ([data_dir] if data_dir else []) + [HERE, os.path.dirname(os.path.abspath(rom_path))]
    src, demo = find_demo(dirs)
    if demo is None:
        print('No copy of the demo found (a 262,144-byte .gb or .gbc with MD5 %s).' % DEMO_MD5)
        print('Put yours next to GraalGB.gbc, in graal-assets/%s/, or give --data DIR.' % VERSION_DIR)
        return 1
    builtin = gpak.read_pack(engine)
    pack = gpak.build_pack(demo_items(demo, builtin))
    rom = gpak.patch(strip_pack(engine), pack)
    if out is None:
        out = os.path.join(os.path.dirname(os.path.abspath(rom_path)), 'GraalGB-original.gbc')
    with open(out, 'wb') as f:
        f.write(rom)
    print('read %s\nwrote %s' % (src, out))
    return 0


def strip_pack(rom):
    rom = bytearray(rom)
    base = gpak.PACK_FIRST_BANK * gpak.BANK_SIZE
    rom[base:] = b'\xff' * (len(rom) - base)
    return bytes(rom)


if __name__ == '__main__':
    sys.exit(main(sys.argv))
