#!/usr/bin/env python3
"""Pull a real client's own resources out of its exe into a build folder.

    python3 -I scripts/res/extract_res.py REAL.exe graal-<ver>-<token> [--heads headsconfig.txt]
    python3 -I scripts/res/extract_res.py --pack graal-<ver>-<token>

The first form copies, from the real program's resource table, the start
window and server list art (RCDATA SCREENIMG*, BUTTON*, LOADINGSCREEN),
the forms the launcher is laid out from (TCONNECTFRAME, TSERVERLISTFRAME,
TSHORTMESSAGE, TRECONNECTFRAME, TSERVERMESSAGE), the offline tutorial
levels (TUTORIAL*), and the program icon (GROUP_ICON MAINICON, as
src/<Program>.ico) into <folder>/src/res/, and writes <folder>/src/res/
manifest.txt (name, size, CRC32 and where each came from). --heads adds
that install's headsconfig.txt as HEADSCONFIG.

Both forms then write <folder>/src/res/<Program>Res.res (committed, so a
build needs neither Python nor the real exe): every other file of src/res/
as an RCDATA resource named after the file (without its extension), in the
Windows .res format. Free Pascal links a .res on every platform ({$R} in
the .dpr) and the program reads it back with FindResource, so the rebuilt
exe carries its own art and needs no original exe beside it.

The real exe is read only; nothing is written next to it. Needs pefile.
"""
import glob
import os
import struct
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
KEEP_PREFIX = ("SCREENIMG", "BUTTON", "LOADINGSCREEN", "TUTORIAL")
KEEP_FORMS = ("TCONNECTFRAME", "TSERVERLISTFRAME", "TSHORTMESSAGE", "TRECONNECTFRAME",
              "TSERVERMESSAGE")


def ext_for(data):
    if data[:2] == b"BM":
        return ".bmp"
    if data[:2] == b"\xff\xd8":
        return ".jpg"
    if data[1:4] == b"PNG":
        return ".png"
    if data[:3] == b"GIF":
        return ".gif"
    if data[:4] == b"TPF0":
        return ".dfm"
    return ".bin"


def extract(exe, folder, heads):
    import pefile
    pe = pefile.PE(exe)
    img = pe.get_memory_mapped_image()
    res = os.path.join(ROOT, folder, "src", "res")
    os.makedirs(res, exist_ok=True)
    for f in glob.glob(os.path.join(res, "*")):
        os.remove(f)
    man = []
    icons = {}
    group = None

    def data_of(entry):
        lang = entry.directory.entries[0]
        d = lang.data.struct
        return bytes(img[d.OffsetToData:d.OffsetToData + d.Size])

    for t in pe.DIRECTORY_ENTRY_RESOURCE.entries:
        for n in t.directory.entries:
            name = str(n.name) if n.name else n.id
            if t.id == 10 and isinstance(name, str):
                if not (name.startswith(KEEP_PREFIX) or name in KEEP_FORMS):
                    continue
                data = data_of(n)
                fn = name + ext_for(data)
                open(os.path.join(res, fn), "wb").write(data)
                man.append((fn, data, "RCDATA " + name))
            elif t.id == 3:
                icons[name] = data_of(n)
            elif t.id == 14 and name == "MAINICON":
                group = data_of(n)
    if group:
        # GRPICONDIR -> ICO: the same entries with file offsets in place of ids
        _, _, count = struct.unpack_from("<HHH", group, 0)
        ents, blobs = [], []
        off = 6 + 16 * count
        for i in range(count):
            w, h, cc, r, planes, bpp, size, iid = struct.unpack_from("<BBBBHHIH", group, 6 + 14 * i)
            blob = icons[iid]
            ents.append(struct.pack("<BBBBHHII", w, h, cc, r, planes, bpp, len(blob), off))
            blobs.append(blob)
            off += len(blob)
        ico = struct.pack("<HHH", 0, 1, count) + b"".join(ents) + b"".join(blobs)
        prog = program(folder)
        open(os.path.join(ROOT, folder, "src", prog + ".ico"), "wb").write(ico)
        man.append((prog + ".ico (src/)", ico, "GROUP_ICON MAINICON"))
    if heads:
        data = open(heads, "rb").read()
        open(os.path.join(res, "HEADSCONFIG.txt"), "wb").write(data)
        man.append(("HEADSCONFIG.txt", data, "the install's headsconfig.txt"))
    with open(os.path.join(res, "manifest.txt"), "w") as m:
        m.write("# pulled from %s (%d bytes, CRC32 %08X) by scripts/res/extract_res.py\n" % (
            os.path.basename(exe), os.path.getsize(exe),
            zlib.crc32(open(exe, "rb").read()) & 0xFFFFFFFF))
        for fn, data, src in man:
            m.write("%-28s %8d  %08X  %s\n" % (fn, len(data), zlib.crc32(data) & 0xFFFFFFFF, src))


def program(folder):
    dpr = glob.glob(os.path.join(ROOT, folder, "src", "*.dpr"))
    return os.path.splitext(os.path.basename(dpr[0]))[0]


def ustr(s):
    return s.upper().encode("utf-16le") + b"\0\0"


def entry(name, data):
    h = struct.pack("<HH", 0xFFFF, 10) + ustr(name)
    if len(h) % 4:
        h += b"\0" * (4 - len(h) % 4)
    h += struct.pack("<IHHII", 0, 0x30, 0x0409, 0, 0)
    return struct.pack("<II", len(data), 8 + len(h)) + h + data + b"\0" * ((4 - len(data) % 4) % 4)


def pack(folder):
    res = os.path.join(ROOT, folder, "src", "res")
    out = struct.pack("<II", 0, 32) + struct.pack("<HHHH", 0xFFFF, 0, 0xFFFF, 0) + b"\0" * 16
    for f in sorted(os.listdir(res)):
        if f == "manifest.txt" or f.endswith(".res"):
            continue
        out += entry(os.path.splitext(f)[0], open(os.path.join(res, f), "rb").read())
    open(os.path.join(res, program(folder) + "Res.res"), "wb").write(out)


def main():
    a = sys.argv[1:]
    if a and a[0] == "--pack":
        pack(a[1])
        return
    heads = None
    if "--heads" in a:
        i = a.index("--heads")
        heads = a[i + 1]
        del a[i:i + 2]
    extract(a[0], a[1], heads)
    pack(a[1])


if __name__ == "__main__":
    main()
