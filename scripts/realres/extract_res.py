#!/usr/bin/env python3
"""Pull every resource out of a real Graal client exe into a build folder.

    python3 scripts/realres/extract_res.py REAL/Graal.exe graal-b9-19981218 RealResB9

Writes, inside the build folder:
  res/                 every resource as a file: forms (Delphi binary .dfm),
                       RCDATA blobs, bitmaps (.bmp), cursors and icons
                       (.cur/.ico), the string tables (strings.txt) and an
                       index (README.txt) with sizes and MD5s
  src/<Unit>.pas       the RCDATA resources compiled into the rebuild, so
                       the program never needs the real exe at run time
  src/<Unit>.ico       the program icon (MAINICON), for the .rc file

The PE reader is self-contained (no pefile), so this runs anywhere with
plain Python 3.
"""
import hashlib
import os
import struct
import sys

TYPES = {1: 'CURSOR', 2: 'BITMAP', 3: 'ICON', 4: 'MENU', 5: 'DIALOG',
         6: 'STRING', 9: 'ACCELERATOR', 10: 'RCDATA', 12: 'GROUP_CURSOR',
         14: 'GROUP_ICON', 16: 'VERSION', 24: 'MANIFEST'}


class PE:
    def __init__(self, data):
        self.d = data
        pe = struct.unpack_from('<I', data, 0x3C)[0]
        assert data[pe:pe + 4] == b'PE\0\0'
        nsec = struct.unpack_from('<H', data, pe + 6)[0]
        optsz = struct.unpack_from('<H', data, pe + 20)[0]
        opt = pe + 24
        magic = struct.unpack_from('<H', data, opt)[0]
        dd = opt + (96 if magic == 0x10B else 112)
        self.res_rva, self.res_size = struct.unpack_from('<II', data, dd + 2 * 8)
        self.secs = []
        so = opt + optsz
        for i in range(nsec):
            va, rsz, rptr = struct.unpack_from('<III', data, so + i * 40 + 8)[0], \
                struct.unpack_from('<I', data, so + i * 40 + 16)[0], \
                struct.unpack_from('<I', data, so + i * 40 + 20)[0]
            vsz = struct.unpack_from('<I', data, so + i * 40 + 8)[0]
            va = struct.unpack_from('<I', data, so + i * 40 + 12)[0]
            self.secs.append((va, max(vsz, rsz), rptr))

    def off(self, rva):
        for va, sz, ptr in self.secs:
            if va <= rva < va + sz:
                return rva - va + ptr
        raise ValueError('rva %x' % rva)

    def resources(self):
        """[(type, name, lang, bytes)] with names as str or int."""
        base = self.off(self.res_rva)
        out = []

        def name_of(e):
            n = struct.unpack_from('<I', self.d, e)[0]
            if n & 0x80000000:
                o = base + (n & 0x7FFFFFFF)
                ln = struct.unpack_from('<H', self.d, o)[0]
                return self.d[o + 2:o + 2 + ln * 2].decode('utf-16le')
            return n

        def entries(dirofs):
            nn, ni = struct.unpack_from('<HH', self.d, base + dirofs + 12)
            for i in range(nn + ni):
                e = base + dirofs + 16 + i * 8
                tgt = struct.unpack_from('<I', self.d, e + 4)[0]
                yield name_of(e), tgt

        for t, td in entries(0):
            for n, nd in entries(td & 0x7FFFFFFF):
                for lang, ld in entries(nd & 0x7FFFFFFF):
                    rva, size = struct.unpack_from('<II', self.d, base + ld)
                    o = self.off(rva)
                    out.append((t, n, lang, self.d[o:o + size]))
        return out


def ico_from_group(group, icons, cursor=False):
    """A .ico/.cur file from a GROUP_ICON entry and its ICON entries."""
    res, typ, cnt = struct.unpack_from('<HHH', group, 0)
    head = struct.pack('<HHH', 0, 2 if cursor else 1, cnt)
    dirs = b''
    blobs = b''
    ofs = 6 + 16 * cnt
    for i in range(cnt):
        e = group[6 + i * 14:6 + i * 14 + 14]
        w, h, cc, r, planes, bits, size, nid = struct.unpack('<BBBBHHIH', e)
        data = icons[nid]
        dirs += struct.pack('<BBBBHHII', w, h, cc, r, planes, bits, len(data), ofs)
        blobs += data
        ofs += len(data)
    return head + dirs + blobs


def bmp_file(dib):
    hsz = struct.unpack_from('<I', dib, 0)[0]
    bits = struct.unpack_from('<H', dib, 14)[0]
    clr = struct.unpack_from('<I', dib, 32)[0] if hsz >= 40 else 0
    if bits <= 8 and clr == 0:
        clr = 1 << bits
    off = 14 + hsz + clr * 4
    return b'BM' + struct.pack('<IHHI', 14 + len(dib), 0, 0, off) + dib


def safe(n):
    return str(n).replace('/', '_').replace('\\', '_')


def main():
    if len(sys.argv) != 4:
        print(__doc__)
        sys.exit(64)
    exe, folder, unit = sys.argv[1:]
    raw = open(exe, 'rb').read()
    pe = PE(raw)
    res = pe.resources()
    rdir = os.path.join(folder, 'res')
    os.makedirs(rdir, exist_ok=True)
    index = []
    icons = {n: d for t, n, l, d in res if t == 3}
    curs = {n: d for t, n, l, d in res if t == 1}
    strings = {}
    rcdata = []
    mainicon = None
    for t, n, l, d in res:
        tn = TYPES.get(t, str(t))
        if t == 10:
            ext = '.dfm' if d[:4] == b'TPF0' else '.bin'
            if n == 'ONLINESTARTLEVEL':
                ext = '.graal'
            fn = safe(n) + ext
            rcdata.append((str(n), d))
        elif t == 2:
            fn = 'bitmap-' + safe(n) + '.bmp'
            d = bmp_file(d)
        elif t == 14:
            fn = 'icon-' + safe(n) + '.ico'
            d = ico_from_group(d, icons)
            if n == 'MAINICON':
                mainicon = d
        elif t == 12:
            fn = 'cursor-' + safe(n) + '.cur'
            d = ico_from_group(d, {k: v[4:] for k, v in curs.items()}, True)
        elif t == 6:
            o = 0
            for i in range(16):
                ln = struct.unpack_from('<H', d, o)[0]
                s = d[o + 2:o + 2 + ln * 2].decode('utf-16le')
                o += 2 + ln * 2
                if s:
                    strings[(n - 1) * 16 + i] = s
            continue
        elif t in (1, 3):
            continue
        else:
            fn = tn.lower() + '-' + safe(n) + '.bin'
        open(os.path.join(rdir, fn), 'wb').write(d)
        index.append((tn, str(n), fn, len(d), hashlib.md5(d).hexdigest()))
    with open(os.path.join(rdir, 'strings.txt'), 'w', encoding='utf-8') as f:
        for k in sorted(strings):
            f.write('%d\t%s\n' % (k, strings[k].replace('\n', '\\n').replace('\r', '\\r')))
    with open(os.path.join(rdir, 'README.txt'), 'w') as f:
        f.write('Resources of the real client, extracted by scripts/realres/extract_res.py.\n')
        f.write('Source: %s, %d bytes, MD5 %s\n\n' % (os.path.basename(exe), len(raw),
                                                    hashlib.md5(raw).hexdigest()))
        f.write('%-12s %-20s %-34s %8s  %s\n' % ('type', 'name', 'file', 'bytes', 'md5'))
        for row in index:
            f.write('%-12s %-20s %-34s %8d  %s\n' % row)
        f.write('%-12s %-20s %-34s %8d\n' % ('STRING', '(%d strings)' % len(strings),
                                            'strings.txt', len(strings)))
    if mainicon:
        open(os.path.join(folder, 'src', unit + '.ico'), 'wb').write(mainicon)
    write_unit(os.path.join(folder, 'src', unit + '.pas'), unit, rcdata,
               os.path.basename(exe), hashlib.md5(raw).hexdigest(), strings)


def write_unit(path, unit, rcdata, exe, md5, strings):
    L = []
    L.append('{ %s: the real client\'s RCDATA resources (its forms and the' % unit)
    L.append('  embedded level), compiled in. GENERATED by')
    L.append('  scripts/realres/extract_res.py from %s (MD5 %s);' % (exe, md5))
    L.append('  do not edit by hand. The same files are in ../res/. }')
    L.append('unit %s;' % unit)
    L.append('')
    L.append('{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}')
    L.append('')
    L.append('interface')
    L.append('')
    L.append('{ The resource Name (any case), e.g. TCONNECTFRAME; False when the')
    L.append('  real exe had none of that name. }')
    L.append('function RealResource(const Name: string; out Data: string): Boolean;')
    L.append('function RealResourceCount: Integer;')
    L.append('function RealResourceName(I: Integer): string;')
    L.append('{ The real exe\'s string table entry Id, or \'\' when there is none. }')
    L.append('function RealString(Id: Integer): string;')
    L.append('')
    L.append('implementation')
    L.append('')
    L.append('uses')
    L.append('  SysUtils;')
    L.append('')
    L.append('{ Each resource is hex text, 2 characters a byte, decoded on use. }')
    for i, (n, d) in enumerate(rcdata):
        h = d.hex().upper()
        L.append('const')
        L.append('  R%d =' % i)
        chunks = [h[j:j + 96] for j in range(0, len(h), 96)] or ['']
        for k, c in enumerate(chunks):
            L.append("    '%s'%s" % (c, ' +' if k < len(chunks) - 1 else ';'))
    L.append('')
    L.append('const')
    L.append('  Names: array[0..%d] of string = (' % (len(rcdata) - 1))
    L.append(',\n'.join("    '%s'" % n for n, d in rcdata) + ');')
    L.append('')
    L.append('function Hex(const S: string): string;')
    L.append('var')
    L.append('  I: Integer;')
    L.append('begin')
    L.append('  SetLength(Result, Length(S) div 2);')
    L.append('  for I := 1 to Length(Result) do')
    L.append("    Result[I] := Chr(StrToInt('$' + Copy(S, I * 2 - 1, 2)));")
    L.append('end;')
    L.append('')
    L.append('function RealResource(const Name: string; out Data: string): Boolean;')
    L.append('begin')
    L.append('  Result := True;')
    for i, (n, d) in enumerate(rcdata):
        L.append("  if SameText(Name, '%s') then begin Data := Hex(R%d); Exit; end;" % (n, i))
    L.append("  Data := '';")
    L.append('  Result := False;')
    L.append('end;')
    L.append('')
    L.append('function RealResourceCount: Integer;')
    L.append('begin')
    L.append('  Result := Length(Names);')
    L.append('end;')
    L.append('')
    L.append('function RealResourceName(I: Integer): string;')
    L.append('begin')
    L.append('  Result := Names[I];')
    L.append('end;')
    L.append('')
    L.append('function RealString(Id: Integer): string;')
    L.append('begin')
    L.append('  case Id of')
    for k in sorted(strings):
        s = strings[k].replace("'", "''")
        s = "'" + s.replace('\r', "'#13'").replace('\n', "'#10'") + "'"
        s = s.replace("''#", "#").replace("#13''", "#13").replace("#10''", "#10")
        L.append('    %d: Result := %s;' % (k, s))
    L.append("  else Result := '';")
    L.append('  end;')
    L.append('end;')
    L.append('')
    L.append('end.')
    open(path, 'w', newline='\n').write('\n'.join(L) + '\n')


if __name__ == '__main__':
    main()
