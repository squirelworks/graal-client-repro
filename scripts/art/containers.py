"""Where the rebuilds keep resource bytes, read and written back in place.

The builds carry resources in six shapes, made by different generators
over time:

  file      a plain file (<build>/res/*, <build>/src/res/*, src/*.ico)
  bytes     a Pascal typed constant   R0: array[0..N] of Byte = ($xx, ...);
            (with an optional R0Len = N + 1; constant before it)
  hex       a Pascal string constant  R0: string = '4A6F...' + '...';
  b64       a Pascal string array     D0: array[0..N] of string = ('...', ...);
            (base64, joined)
  winres    a Windows .res file: one RCDATA (or other) entry per resource
  (ico)     icons are plain files; their insides are handled by the art code

Each blob is found with the name the generator gave it (a resource name
such as SCREENIMG1, a path such as levels/heads/head0.png, or a constant
name such as BSCREENIMG2_64b453a6) so the art code can tell what it is.
Rewriting keeps everything around a blob byte for byte.
"""
import base64
import os
import re
import struct

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# ------------------------------------------------------------------ discovery

RES_UNIT = re.compile(r'(^|/)(Res[0-9A-Za-z]*|RealRes[0-9A-Za-z]*|GRes20x)\.pas$')


def build_dirs():
    return sorted(d for d in os.listdir(ROOT)
                  if os.path.isdir(os.path.join(ROOT, d)) and
                  (d.startswith('graal') or d.startswith('zelda') or d.startswith('javagraal')))


def containers():
    """Every container under the repository root, as (kind, path)."""
    out = []
    for b in build_dirs():
        for base, dirs, files in os.walk(os.path.join(ROOT, b)):
            dirs.sort()
            rel = os.path.relpath(base, ROOT).replace(os.sep, '/')
            in_res = '/res' in '/' + rel.split('/', 1)[-1] or rel.endswith('/res')
            for f in sorted(files):
                p = rel + '/' + f
                if f.endswith('.res'):
                    out.append(('winres', p))
                elif f.endswith('.pas') and RES_UNIT.search(p):
                    out.append(('pas', p))
                elif in_res and '/res' in p:
                    out.append(('file', p))
                elif f.endswith('.ico') and '/src/' in p:
                    out.append(('file', p))
    out.append(('pas', 'common/GRes20x.pas'))
    return out


# ------------------------------------------------------------------ Pascal

BYTES_RE = re.compile(
    r'(?P<len>^  (?P<lname>\w+)Len = (?P<lval>\d+);\n)?'
    r'^  (?P<name>\w+): array\[0\.\.(?P<hi>\d+)\] of Byte = \((?P<body>[^;]*?)\);\n',
    re.M | re.S)
HEX_RE = re.compile(
    r"^  (?P<name>\w+): string =\n(?P<body>(?:    '[0-9A-Fa-f]*'(?: \+)?\n)+?)(?=    '[0-9A-Fa-f]*';\n|)"
    r"(?P<last>    '[0-9A-Fa-f]*';\n)", re.M)
B64_RE = re.compile(
    r"^  (?P<name>\w+): array\[0\.\.(?P<hi>\d+)\] of string = \(\n(?P<body>(?:    '[A-Za-z0-9+/=]*',?\)?;?\n)+)",
    re.M)


def _pas_bytes_decode(body):
    toks = re.findall(r'\$([0-9a-fA-F]{2})|(?<![\w$])(\d+)(?![\w])', body)
    out = bytearray()
    for h, d in toks:
        out.append(int(h, 16) if h else int(d))
    return bytes(out)


def _pas_bytes_encode(name, data, lname):
    s = ''
    if lname is not None:
        s += '  %sLen = %d;\n' % (lname, len(data))
    if not data:
        return s + '  %s: array[0..0] of Byte = (0);\n' % name
    rows = []
    for i in range(0, len(data), 18):
        rows.append('    ' + ','.join('$%02x' % c for c in data[i:i + 18]))
    return s + '  %s: array[0..%d] of Byte = (\n%s);\n' % (name, len(data) - 1, ',\n'.join(rows))


def _hex_encode(name, data):
    h = data.hex().upper()
    rows = [h[i:i + 96] for i in range(0, len(h), 96)] or ['']
    lines = ["    '%s'" % r for r in rows]
    return '  %s: string =\n%s;\n' % (name, ' +\n'.join(lines))


def _b64_encode(name, data):
    e = base64.b64encode(data).decode('ascii')
    rows = [e[i:i + 200] for i in range(0, len(e), 200)] or ['']
    return '  %s: array[0..%d] of string = (\n%s);\n' % (
        name, len(rows) - 1, ',\n'.join("    '%s'" % r for r in rows))


def pas_blobs(text):
    """(start, end, name, data, encoder) for each blob in a unit's text."""
    out = []
    for m in BYTES_RE.finditer(text):
        lname = m.group('lname')
        data = _pas_bytes_decode(m.group('body'))
        if lname is not None:
            data = data[:int(m.group('lval'))]
        n = m.group('name')
        out.append((m.start(), m.end(), n, data,
                    lambda d, n=n, ln=lname: _pas_bytes_encode(n, d, ln)))
    for m in re.finditer(r"^  (?P<name>\w+): string =\n(?P<body>(?:    '[0-9A-Fa-f]*'(?: \+|;)\n)+)", text, re.M):
        body = m.group('body')
        h = ''.join(re.findall(r"'([0-9A-Fa-f]*)'", body))
        if len(h) % 2:
            continue
        n = m.group('name')
        out.append((m.start(), m.end(), n, bytes.fromhex(h), lambda d, n=n: _hex_encode(n, d)))
    for m in B64_RE.finditer(text):
        body = m.group('body')
        parts = re.findall(r"'([A-Za-z0-9+/=]*)'", body)
        n = m.group('name')
        if n == 'Names' or not parts:
            continue
        try:
            data = base64.b64decode(''.join(parts), validate=True)
        except Exception:
            continue
        out.append((m.start(), m.end(), n, data, lambda d, n=n: _b64_encode(n, d)))
    out.sort(key=lambda t: t[0])
    return out


def pas_names(text):
    """Map constant name -> resource name the unit gives it, where the unit
    says (Names arrays, case/if chains, Lookup tables)."""
    names = {}
    m = re.search(r"^  Names: array\[0\.\.\d+\] of string = \((.*?)\);", text, re.M | re.S)
    if m:
        lst = re.findall(r"'([^']*)'", m.group(1))
        for i, n in enumerate(lst):
            names['R%d' % i] = n
            names['D%d' % i] = n
    for m in re.finditer(r"N = '([^']+)' then Data := \w+\((\w+)\)", text):
        names[m.group(2)] = m.group(1)
    for m in re.finditer(r"'([^']+)'\s*then\s*Data\s*:=\s*\w+\((\w+)", text):
        names.setdefault(m.group(2), m.group(1))
    # GRes20x-style B<NAME>_<crc>
    for m in re.finditer(r'^  (B([A-Z0-9_]+)_[0-9a-f]{8}):', text, re.M):
        names.setdefault(m.group(1), m.group(2))
    # make_res222: a Keys table of names in the order of D0, D1, ...
    m = re.search(r"Keys: array\[0\.\.\d+\] of string = \((.*?)\);", text, re.S)
    if m:
        for i, n in enumerate(re.findall(r"'([^']*)'", m.group(1))):
            names.setdefault('D%d' % i, n)
    # extract_1x: RConnectFrame -> ConnectFrame
    for m in re.finditer(r'^  R([A-Z][A-Za-z]+)(?:Len)? ?[:=]', text, re.M):
        names.setdefault('R' + m.group(1), m.group(1))
    return names


# ------------------------------------------------------------------ .res

def _res_str(b, p):
    if struct.unpack_from('<H', b, p)[0] == 0xFFFF:
        return struct.unpack_from('<H', b, p + 2)[0], p + 4
    s = ''
    while True:
        c = struct.unpack_from('<H', b, p)[0]
        p += 2
        if c == 0:
            break
        s += chr(c)
    return s, p


def winres_entries(b):
    """[(header_bytes, type, name, data)] of a .res file."""
    out = []
    p = 0
    while p + 8 <= len(b):
        size, hsize = struct.unpack_from('<II', b, p)
        hdr = b[p:p + hsize]
        t, q = _res_str(b, p + 8)
        n, q = _res_str(b, q)
        data = b[p + hsize:p + hsize + size]
        out.append((hdr, t, n, data))
        p += hsize + size
        p = (p + 3) & ~3
    return out


def winres_write(entries):
    out = bytearray()
    for hdr, t, n, data in entries:
        hdr = bytearray(hdr)
        struct.pack_into('<I', hdr, 0, len(data))
        out += hdr + data
        while len(out) % 4:
            out.append(0)
    return bytes(out)


# ------------------------------------------------------------------ uniform API

def read_blobs(kind, path):
    """[(key, name_hint, data)] of one container."""
    full = os.path.join(ROOT, path)
    if kind == 'file':
        return [(None, path, open(full, 'rb').read())]
    if kind == 'winres':
        out = []
        for i, (hdr, t, n, data) in enumerate(winres_entries(open(full, 'rb').read())):
            if data:
                out.append((i, str(n), data))
        return out
    text = open(full, encoding='latin1').read()
    names = pas_names(text)
    return [(n, names.get(n, n), d) for (_, _, n, d, _) in pas_blobs(text)]


def write_blobs(kind, path, new):
    """Replace blobs by key (dict key -> bytes). Returns True when changed."""
    full = os.path.join(ROOT, path)
    if kind == 'file':
        if None in new:
            old = open(full, 'rb').read()
            if old != new[None]:
                open(full, 'wb').write(new[None])
                return True
        return False
    if kind == 'winres':
        b = open(full, 'rb').read()
        ents = winres_entries(b)
        ents = [(h, t, n, new.get(i, d)) for i, (h, t, n, d) in enumerate(ents)]
        nb = winres_write(ents)
        if nb != b:
            open(full, 'wb').write(nb)
            return True
        return False
    text = open(full, encoding='latin1').read()
    parts = []
    last = 0
    for (s, e, n, d, enc) in pas_blobs(text):
        if n in new and new[n] != d:
            parts.append(text[last:s])
            parts.append(enc(new[n]))
            last = e
    if not parts:
        return False
    parts.append(text[last:])
    nt = ''.join(parts)
    # keep any Count/length literal next to a base64 table in step: none use one
    open(full, 'w', encoding='latin1', newline='').write(nt)
    return True
