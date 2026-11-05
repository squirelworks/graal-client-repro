#!/usr/bin/env python3
"""Pull the resources out of the real 2.0x clients and compile them in.

For each 2.0x build folder this reads that build's own original Graal.exe
and writes:

  graal-<build>/src/Res<Program>.pas   that exe's RCDATA resources (the
                                        launcher art, every form, the
                                        Training levels) as Pascal bytes
  graal-<build>/src/<Program>.ico       its MAINICON, for src/<Program>.rc
  common/GRes20x.pas                    the bytes two or more of the 2.0x
                                        exes share, once

so each rebuilt program carries its own client's resources and needs no
original program next to it. Bytes that are the same in several exes are
kept once in common/GRes20x.pas; each folder's unit says which of them its
exe has, so every program still holds exactly its own exe's set.

    python3 scripts/res20x/make_res20x.py DIR

DIR holds the original installs, one folder per build as in the project's
archives: "Graal v2.0/Graal.exe", "Graal v2.0 rev1/Graal.exe", ...
(any depth below DIR). Delphi's own RCDATA (DVCLAL, PACKAGEINFO) is left
out; it belongs to the compiler, not to Graal.
"""
import hashlib
import os
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# build folder -> (program name, install folder name)
BUILDS = [
    ("graal-2.0-GNW24011", "Graal200", "Graal v2.0"),
    ("graal-2.0r1-GNW24011", "Graal200r1", "Graal v2.0 rev1"),
    ("graal-2.0r2-GNW24011", "Graal200r2", "Graal v2.0 rev2"),
    ("graal-2.0r3-GNW24011", "Graal200r3", "Graal v2.0 rev3"),
    ("graal-2.01-GNW23021", "Graal201", "Graal v2.01"),
    ("graal-2.01r1-GNW23021", "Graal201r1", "Graal v2.01 rev1"),
    ("graal-2.02-GNW15041", "Graal202", "Graal v2.02"),
    ("graal-2.02r1-GNW15041", "Graal202r1", "Graal v2.02 rev1"),
    ("graal-2.02r2-GNW20041", "Graal202r2", "Graal v2.02 rev2"),
    ("graal-2.03-GNW06051", "Graal203", "Graal v2.03"),
    ("graal-2.04-GNW24061", "Graal204", "Graal v2.04"),
    ("graal-2.05-GNW03081", "Graal205", "Graal v2.05"),
    ("graal-2.05r1-GNW03081", "Graal205", "Graal v2.05 rev1"),
    ("graal-2.05r2-GNW03081", "Graal205", "Graal v2.05 rev2"),
]
SKIP = {"DVCLAL", "PACKAGEINFO"}


def pe_resources(path):
    """{(type, name): bytes} for the first language of every resource."""
    d = open(path, "rb").read()
    pe = struct.unpack_from("<I", d, 0x3C)[0]
    nsec = struct.unpack_from("<H", d, pe + 6)[0]
    optsz = struct.unpack_from("<H", d, pe + 20)[0]
    opt = pe + 24
    rsrc_rva = struct.unpack_from("<I", d, opt + 96 + 2 * 8)[0]
    secs = []
    for i in range(nsec):
        s = pe + 24 + optsz + i * 40
        va, vsz = struct.unpack_from("<II", d, s + 12)[::-1][::-1]
        vsz, va, rawsz, raw = struct.unpack_from("<IIII", d, s + 8)
        secs.append((va, max(vsz, rawsz), raw))

    def off(rva):
        for va, sz, raw in secs:
            if va <= rva < va + sz:
                return rva - va + raw
        raise ValueError("rva")

    base = off(rsrc_rva)

    def entries(o):
        n1, n2 = struct.unpack_from("<HH", d, o + 12)
        for i in range(n1 + n2):
            nm, ch = struct.unpack_from("<II", d, o + 16 + i * 8)
            if nm & 0x80000000:
                p = base + (nm & 0x7FFFFFFF)
                ln = struct.unpack_from("<H", d, p)[0]
                key = d[p + 2:p + 2 + ln * 2].decode("utf-16le")
            else:
                key = nm
            yield key, ch

    out = {}
    for t, c1 in entries(base):
        for n, c2 in entries(base + (c1 & 0x7FFFFFFF)):
            for _lang, c3 in entries(base + (c2 & 0x7FFFFFFF)):
                rva, size = struct.unpack_from("<II", d, base + c3)
                out[(t, n)] = d[off(rva):off(rva) + size]
                break
    return out


def ico_file(res, group):
    """The .ico of GROUP_ICON group (type 14) from its RT_ICON parts."""
    g = res[(14, group)]
    _r, _t, n = struct.unpack_from("<HHH", g, 0)
    imgs, dirs = [], []
    for i in range(n):
        w, h, cc, r, planes, bc, size, ident = struct.unpack_from("<BBBBHHIH", g, 6 + i * 14)
        imgs.append(res[(3, ident)])
        dirs.append((w, h, cc, r, planes, bc, len(imgs[-1])))
    head = struct.pack("<HHH", 0, 1, n)
    pos = 6 + 16 * n
    for (w, h, cc, r, planes, bc, size), img in zip(dirs, imgs):
        head += struct.pack("<BBBBHHII", w, h, cc, r, planes, bc, size, pos)
        pos += size
    return head + b"".join(imgs)


def pas_bytes(name, data):
    lines = []
    for i in range(0, len(data), 24):
        lines.append("    " + ",".join("$%02x" % b for b in data[i:i + 24]))
    return "  %s: array[0..%d] of Byte = (\n%s);\n" % (name, len(data) - 1, ",\n".join(lines))


def find_exes(top):
    found = {}
    for dp, _dn, fn in os.walk(top):
        if "Graal.exe" in fn:
            found[os.path.basename(dp)] = os.path.join(dp, "Graal.exe")
    return found


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 64
    exes = find_exes(sys.argv[1])
    sets = {}
    for folder, prog, inst in BUILDS:
        if inst not in exes:
            print("missing:", inst)
            return 1
        res = pe_resources(exes[inst])
        rc = {n: v for (t, n), v in res.items() if t == 10 and isinstance(n, str) and n not in SKIP}
        sets[folder] = (prog, rc, ico_file(res, "MAINICON"))
    # blobs in two or more exes go to the common unit
    users = {}
    for folder, (prog, rc, ico) in sets.items():
        for n, v in rc.items():
            users.setdefault(hashlib.sha1(v).hexdigest(), set()).add(folder)
    blobs = {}
    for folder, (prog, rc, ico) in sets.items():
        for n, v in rc.items():
            blobs[hashlib.sha1(v).hexdigest()] = (n, v)
    shared = sorted(h for h, u in users.items() if len(u) > 1)
    ids = {h: "B%s_%s" % (blobs[h][0], h[:8]) for h in shared}

    with open(os.path.join(ROOT, "common", "GRes20x.pas"), "w", newline="\n") as f:
        f.write("""{ GRes20x: resources two or more of the original 2.0x clients (2.0 to
  2.05 rev 2) carry byte for byte the same: the launcher art, most forms
  and the Training levels. GENERATED by scripts/res20x/make_res20x.py from
  the original Graal.exe files; do not edit by hand. Each build's own
  src/Res<Program>.pas says which of these its exe has. }
unit GRes20x;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

const
""")
        for h in shared:
            f.write(pas_bytes(ids[h], blobs[h][1]))
        f.write("""
{ Bytes as a string. }
function ResBytes(const B: array of Byte): string;

implementation

function ResBytes(const B: array of Byte): string;
begin
  SetLength(Result, Length(B));
  if Length(B) > 0 then Move(B[0], Result[1], Length(B));
end;

end.
""")

    for folder, (prog, rc, ico) in sets.items():
        unit = "Res" + prog
        names = sorted(rc)
        own = [n for n in names if hashlib.sha1(rc[n]).hexdigest() not in ids]
        with open(os.path.join(ROOT, folder, "src", unit + ".pas"), "w", newline="\n") as f:
            f.write("""{ %s: the resources of this build's original Graal.exe (RCDATA: the
  launcher art, every form, the Training levels), compiled in, so this
  program carries its own client's resources. GENERATED by
  scripts/res20x/make_res20x.py; do not edit by hand. Resources the other
  2.0x clients share byte for byte are in common/GRes20x.pas. }
unit %s;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

{ RCDATA resource Name (any case) of the original exe; False if it had
  none. }
function ExeResource(const Name: string; out Data: string): Boolean;

implementation

uses
  SysUtils, GRes20x;

""" % (unit, unit))
            if own:
                f.write("const\n")
                for n in own:
                    f.write(pas_bytes("R" + n, rc[n]))
                f.write("\n")
            f.write("function ExeResource(const Name: string; out Data: string): Boolean;\nvar\n  N: string;\nbegin\n  Result := True;\n  N := UpperCase(Name);\n")
            for i, n in enumerate(names):
                h = hashlib.sha1(rc[n]).hexdigest()
                ref = ids.get(h, "R" + n)
                f.write("  %sif N = '%s' then Data := ResBytes(%s)\n" % ("" if i == 0 else "else ", n, ref))
            f.write("  else\n  begin\n    Data := '';\n    Result := False;\n  end;\nend;\n\nend.\n")
        with open(os.path.join(ROOT, folder, "src", prog + ".ico"), "wb") as f:
            f.write(ico)
        print(folder, len(names), "resources,", len(own), "of its own")
    return 0


if __name__ == "__main__":
    sys.exit(main())
