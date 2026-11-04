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

# Where the demo keeps its data (bank, address). These are data locations
# only, from the shared notes on the ROM's layout.
TILESET_PTRS = (2, 0x66EA)
FONT = (2, 0x6000, 82)
WALK_BITS = (2, 0x6520)
BG_PALETTES = (2, 0x65A0, 5)
ANIM0 = (2, 0x66EE)          # 4 frames of tile 3, tileset 0
ANIM1 = (2, 0x672E)          # 4 frames of tiles $26-$27, tileset 1
ANIM0B = (2, 0x67AE)         # 2 frames of tile $fb, tileset 0
HEADS = (3, 0x5B77, 20)
CHAR_TYPES = (3, 0x6861)     # 31 x (name, palette, head) pointers
LIFTABLE = (1, 0x7753)       # 4 kinds x (top-left, top-right)
LIFTED = (1, 0x775F)         # 4 kinds x 2x2 tiles
ROOM_PTRS = (4, 0x4000)

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


def demo_items(rom, builtin):
    items = dict(builtin)
    t0 = rom.word(*TILESET_PTRS)
    t1 = rom.word(TILESET_PTRS[0], TILESET_PTRS[1] + 2)
    items[gpak.TILES0] = rom.bytes(2, t0, 4096)
    items[gpak.TILES1] = rom.bytes(2, t1, 4096)
    # the demo's font, window frame and arrows; capitals use BG palette 1
    items[gpak.FONT] = bytes([FONT[2], 1]) + rom.bytes(FONT[0], FONT[1], FONT[2] * 16)
    items[gpak.WALK] = rom.bytes(WALK_BITS[0], WALK_BITS[1], 64)
    items[gpak.BGPAL] = bytes([BG_PALETTES[2]]) + rom.bytes(BG_PALETTES[0], BG_PALETTES[1], BG_PALETTES[2] * 64)
    a0 = rom.bytes(*ANIM0, 64)
    a1 = rom.bytes(*ANIM1, 128)
    a0b = rom.bytes(*ANIM0B, 32)
    anim = bytearray([2, 3, 4]) + a0
    anim += bytes([0xFB, 2]) + a0b
    anim += bytes([2, 0x26, 4]) + b''.join(a1[f * 32:f * 32 + 16] for f in range(4))
    anim += bytes([0x27, 4]) + b''.join(a1[f * 32 + 16:f * 32 + 32] for f in range(4))
    items[gpak.ANIM] = bytes(anim)
    items[gpak.HEADS] = bytes([HEADS[2]]) + rom.bytes(HEADS[0], HEADS[1], HEADS[2] * 128)
    chars = bytearray([gpak.NUM_CHARS])
    for k in range(gpak.NUM_CHARS):
        b, a = CHAR_TYPES
        np_, pp, hp = (rom.word(b, a + k * 6 + i) for i in (0, 2, 4))
        name = ascii_to_codes(rom.cstr(3, np_))[:gpak.NAME_LEN]
        rec = bytearray(name + bytes(gpak.NAME_LEN - len(name)))
        rec += rom.bytes(3, pp, 24)
        rec += bytes([(hp - HEADS[1]) // 128, SWORD_COLOUR.get(k, 0), A_ITEM.get(k, gpak.A_NONE), 0, 0, 0])
        chars += rec
    items[gpak.CHARS] = bytes(chars)
    lt = rom.bytes(*LIFTABLE, 8)
    lifted = rom.bytes(*LIFTED, 16)
    items[gpak.LIFT] = bytes(lt[0::2]) + bytes(lt[1::2]) + lifted + bytes(LIFT_LOOK)
    items[gpak.START] = START
    for r in range(gpak.NUM_ROOMS):
        bank = 4 + r // 5
        hdr = rom.bytes(bank, rom.word(ROOM_PTRS[0], ROOM_PTRS[1] + 2 * r), 13)
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
    pack = gpak.build_pack(demo_items(Rom(demo), builtin))
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
