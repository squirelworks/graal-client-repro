#!/usr/bin/env python3
"""Pack the files of a real install that a rebuild reads into the rebuild.

    python3 scripts/res/install_res.py INSTALL_DIR <folder>

Picks what the game and its start window read from an install (the tile
and sprite sheets, arrays, bodies, heads, swords, shields, ganis, the
Training and start levels, maps, sounds, language files) and leaves out
programs, documents, settings and the big world folders. Writes

- <folder>/src/res/<Program>Install.res: each file as an RCDATA resource
  named F_ and its path in upper case with every other character as _
  (levels/heads/head0.gif: F_LEVELS_HEADS_HEAD0_GIF), and FILELIST, the
  paths one per line;
- <folder>/src/res/install-manifest.txt: path, size and CRC32 of each.

The program links the .res ({$R} in the .dpr) and common/GResFiles.pas
hands the files out when the folder it runs in has none, so the rebuilt
exe runs in an empty folder with its original's art. The install is read
only.
"""
import os
import re
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from extract_res import ROOT, entry, program  # noqa: E402

SKIPEXT = {".exe", ".dll", ".idc", ".doc", ".sig", ".zip", ".rtf", ".ini", ".html", ".mng"}
ROOTEXT = {".png", ".gif", ".jpg", ".dat", ".ttf", ".txt", ".wav", ".mid", ".nw", ".graal", ".gmap"}
SKIPROOT = re.compile(r"^(graalconfig|listserver|newfeatures.*|readme.*|filenamecache|buddyaccounts|"
                      r"dinputdll-bug|controlnpc.*|levelformat|levelpics|newworldislands|dc\..*|"
                      r".*map\.txt|bigmap|minimap)\.txt$", re.I)
LEVDIRS = {"ganis", "heads", "bodies", "swords", "shields", "tutorial", "weather", "npcs", "images",
           "hats", "letters", "baddies", "backpals", "emoticons", "horses", "graphics", "maps",
           "tiledefs", "weapons", "critters", "menuskins", "webgifs", "smilies", "bomys", "midis", "sneakpeek"}


def select(r):
    out = []
    for f in sorted(os.listdir(r)):
        p = os.path.join(r, f)
        e = os.path.splitext(f)[1].lower()
        if os.path.isfile(p) and e in ROOTEXT and not SKIPROOT.match(f):
            out.append(f)
    for d in ("languages", "sounds", "maps"):
        if os.path.isdir(os.path.join(r, d)):
            for f in sorted(os.listdir(os.path.join(r, d))):
                if os.path.isfile(os.path.join(r, d, f)):
                    out.append(d + "/" + f)
    lv = os.path.join(r, "levels")
    if os.path.isdir(lv):
        for f in sorted(os.listdir(lv)):
            p = os.path.join(lv, f)
            if os.path.isfile(p) and os.path.splitext(f)[1].lower() in (".nw", ".graal", ".gmap", ".png", ".gif", ".txt"):
                out.append("levels/" + f)
            elif os.path.isdir(p) and f.lower() in LEVDIRS:
                for dp, _, fs in sorted(os.walk(p)):
                    for g in sorted(fs):
                        if os.path.splitext(g)[1].lower() not in SKIPEXT:
                            out.append(os.path.relpath(os.path.join(dp, g), r).replace(os.sep, "/"))
    return out


def resname(path):
    return "F_" + re.sub(r"[^A-Z0-9]", "_", path.upper())


def main():
    inst, folder = sys.argv[1], sys.argv[2]
    files = select(inst)
    names = {}
    for f in files:
        n = resname(f)
        if n in names:
            sys.exit("two files share the resource name %s: %s, %s" % (n, names[n], f))
        names[n] = f
    res = os.path.join(ROOT, folder, "src", "res")
    os.makedirs(res, exist_ok=True)
    import struct
    out = struct.pack("<II", 0, 32) + struct.pack("<HHHH", 0xFFFF, 0, 0xFFFF, 0) + b"\0" * 16
    out += entry("FILELIST", ("\n".join(files) + "\n").encode("latin-1"))
    total = 0
    with open(os.path.join(res, "install-manifest.txt"), "w") as m:
        m.write("# files of the %s install carried in %sInstall.res (scripts/res/install_res.py)\n"
                % (folder, program(folder)))
        for f in files:
            data = open(os.path.join(inst, f), "rb").read()
            total += len(data)
            out += entry(resname(f), data)
            m.write("%-48s %8d  %08X\n" % (f, len(data), zlib.crc32(data) & 0xFFFFFFFF))
    open(os.path.join(res, program(folder) + "Install.res"), "wb").write(out)
    print("%s: %d files, %d KB" % (folder, len(files), total // 1024))


if __name__ == "__main__":
    main()
