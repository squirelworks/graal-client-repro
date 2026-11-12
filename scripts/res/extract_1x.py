#!/usr/bin/env python3
"""Pull what a real 1.x Graal.exe carries into its rebuild's folder.

    python3 scripts/res/extract_1x.py <folder> <Graal.exe> [<install dir>]

Writes, in <folder>:
  res/ConnectFrame.dfm   the start dialog (RCDATA TCONNECTFRAME, Delphi
                         binary form; its pictures are inside it)
  res/Adventure.dfm      the game window's form (RCDATA TADVENTURE)
  res/Options.dfm        the F1 window's form (RCDATA TOPTIONS), when the
                         exe has one
  res/OnlineStart.graal  the online start level, when the exe has one
                         (RCDATA ONLINESTARTLEVEL, 1.1 and 1.1.9)
  res/characters.txt     the character list of the start dialog, in
                         headsconfig.txt's form: the install's own
                         headsconfig.txt, or, for the builds without one
                         (1.1, 1.1.9), the table compiled into the exe
  res/*.txt              each form as text, for reading and diffs
  src/<Program>.ico      the program's icon (GROUP_ICON MAINICON)
  src/Res<Suffix>.pas    all of the above compiled in (generated)

Needs pefile (pip install pefile).
"""
import os, re, struct, sys
import pefile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from dfm_text import dfm_to_text  # noqa: E402

COLORS = ['white', 'yellow', 'orange', 'pink', 'red', 'darkred', 'lightgreen',
          'green', 'darkgreen', 'lightblue', 'blue', 'darkblue', 'brown',
          'cynober', 'purple', 'darkpurple', 'lightgray', 'gray', 'black',
          'transparent']


def resources(pe):
    out = {}
    for t in pe.DIRECTORY_ENTRY_RESOURCE.entries:
        tid = t.id if t.name is None else str(t.name)
        for n in t.directory.entries:
            nid = n.id if n.name is None else str(n.name)
            l = n.directory.entries[0]
            d = l.data.struct
            out[(tid, nid)] = pe.get_data(d.OffsetToData, d.Size)
    return out


def make_ico(res, group):
    g = res[(14, group)]
    _, _, count = struct.unpack_from('<HHH', g, 0)
    entries, images = [], []
    for i in range(count):
        w, h, c, r, planes, bits, size, iid = struct.unpack_from('<BBBBHHIH', g, 6 + i * 14)
        img = res[(3, iid)]
        entries.append((w, h, c, r, planes, bits, len(img)))
        images.append(img)
    out = struct.pack('<HHH', 0, 1, count)
    off = 6 + 16 * count
    for e, img in zip(entries, images):
        out += struct.pack('<BBBBHHII', *e, off)
        off += len(img)
    return out + b''.join(images)


def builtin_characters(pe):
    """1.1 / 1.1.9: the names are a typed constant array of strings, right
    after it five colour indices (integers) per name."""
    d = pe.__data__
    base = pe.OPTIONAL_HEADER.ImageBase
    lit = d.find(b'\xff\xff\xff\xff\x0b\x00\x00\x00Fung Si Yan\x00')
    if lit < 0:
        return None
    va = base + pe.get_rva_from_offset(lit + 8)
    tab = d.find(struct.pack('<I', va))
    names = []
    p = tab
    while True:
        (ptr,) = struct.unpack_from('<I', d, p)
        off = pe.get_offset_from_rva(ptr - base) if base <= ptr < base + 0x1000000 else None
        if off is None or d[off - 4:off] != struct.pack('<I', len(d[off:d.find(b'\0', off)])):
            break
        names.append(d[off:d.find(b'\0', off)].decode('latin1'))
        p += 4
    lines = []
    for i, n in enumerate(names):
        cols = struct.unpack_from('<5i', d, p + i * 20)
        # the head of the i-th name is column i of heads.gif (head<i>.gif);
        # the exe has no gender in its table
        lines.append('%s=head%d.gif,male,%s' % (n, i, ','.join(COLORS[c] for c in cols)))
    return '\r\n'.join(lines) + '\r\n'


def pas_bytes(name, data):
    if not data:
        return '  %s: array[0..0] of Byte = (0);\n  %sLen = 0;\n' % (name, name)
    rows = []
    for i in range(0, len(data), 18):
        rows.append('    ' + ','.join('$%02x' % b for b in data[i:i + 18]))
    return ('  %sLen = %d;\n  %s: array[0..%d] of Byte = (\n%s);\n'
            % (name, len(data), name, len(data) - 1, ',\n'.join(rows)))


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    folder, exe = sys.argv[1], sys.argv[2]
    install = sys.argv[3] if len(sys.argv) > 3 else os.path.dirname(exe)
    pe = pefile.PE(exe)
    res = resources(pe)
    resdir = os.path.join(folder, 'res')
    src = os.path.join(folder, 'src')
    os.makedirs(resdir, exist_ok=True)
    dpr = [f for f in os.listdir(src) if f.endswith('.dpr')][0]
    prog = dpr[:-4]
    suffix = prog[len('Graal'):]

    blobs = {}
    for rname, fname, key in (('TCONNECTFRAME', 'ConnectFrame.dfm', 'ConnectFrame'),
                              ('TADVENTURE', 'Adventure.dfm', 'Adventure')):
        data = res[(10, rname)]
        open(os.path.join(resdir, fname), 'wb').write(data)
        open(os.path.join(resdir, fname[:-4] + '.txt'), 'w', newline='\n').write(dfm_to_text(data))
        blobs[key] = data
    opt = res.get((10, 'TOPTIONS'))
    if opt:
        open(os.path.join(resdir, 'Options.dfm'), 'wb').write(opt)
        open(os.path.join(resdir, 'Options.txt'), 'w', newline='\n').write(dfm_to_text(opt))
    blobs['Options'] = opt or b''
    osl = res.get((10, 'ONLINESTARTLEVEL'))
    if osl:
        open(os.path.join(resdir, 'OnlineStart.graal'), 'wb').write(osl)
    blobs['OnlineStart'] = osl or b''

    hc = os.path.join(install, 'headsconfig.txt')
    if os.path.exists(hc):
        chars = open(hc, 'rb').read()
        how = "the install's headsconfig.txt"
    else:
        chars = builtin_characters(pe).encode('latin1')
        how = "the table compiled into the exe"
    open(os.path.join(resdir, 'characters.txt'), 'wb').write(chars)
    blobs['Characters'] = chars

    open(os.path.join(src, prog + '.ico'), 'wb').write(make_ico(res, 'MAINICON'))

    with open(os.path.join(src, 'Res%s.pas' % suffix), 'w', newline='\n') as f:
        f.write('{ Res%s: what the real %s carries, compiled in: its start dialog\n'
                '  and game window forms (with their pictures), its character list\n'
                '  (from %s) and, when it has one, its online start\n'
                '  level. GENERATED by scripts/res/extract_1x.py from res/; do not\n'
                '  edit by hand. }\n' % (suffix, os.path.basename(exe), how))
        f.write('unit Res%s;\n\n{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}\n\ninterface\n\n' % suffix)
        f.write('function ResConnectFrame: string;\nfunction ResAdventure: string;\n'
                'function ResCharacters: string;\n{ \'\' when the exe has none }\n'
                'function ResOnlineStart: string;\n{ the F1 window\'s form; \'\' when the exe has none }\n'
                'function ResOptions: string;\n\nimplementation\n\nconst\n')
        for k in ('ConnectFrame', 'Adventure', 'Characters', 'OnlineStart', 'Options'):
            f.write(pas_bytes('R' + k, blobs[k]))
        f.write('\nfunction Bytes(const B: array of Byte; Len: Integer): string;\nbegin\n'
                '  SetLength(Result, Len);\n  if Len > 0 then Move(B[0], Result[1], Len);\nend;\n\n')
        for k in ('ConnectFrame', 'Adventure', 'Characters', 'OnlineStart', 'Options'):
            f.write('function Res%s: string;\nbegin\n  Result := Bytes(R%s, R%sLen);\nend;\n\n' % (k, k, k))
        f.write('end.\n')
    print('%s: %s (%d characters from %s)' % (folder, prog, chars.count(b'\n'), how))


if __name__ == '__main__':
    main()
