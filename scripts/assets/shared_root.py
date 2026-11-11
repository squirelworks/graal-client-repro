#!/usr/bin/env python3
"""Repack a graal-assets folder as one shared root: every program in one
folder, one copy of each file, and per version only what differs.

  shared_root.py SRC OUT.zip [--readme FILE] [--chain VERSION=A;B ...]
  shared_root.py --check DIR SRC [--chain VERSION=A;B ...]

SRC is a graal-assets folder (one folder per version, as needed_assets.py
cuts it, or graal-assets-<version>.zip extracted). OUT.zip extracts into
the folder that holds the programs:

  <root>/
    Graal139.exe  Graal222.exe ...   (from the release zips, not this zip)
    levels/ sounds/ maps/ pics1.gif  one copy of each file
    _clients/<version>/              that version's files whose bytes (or
                                     path) differ from the root copy
    _clients/<version>/files.txt     the root files that version's install
                                     had, one path per line
    README-assets.txt

What a version sees is its install as SRC gives it, folding in the
fallback folders of its label (b12 reads b11, 1.1 reads 1.1.9, b15, b11,
...): its own folder under _clients/ first, then the root files its
files.txt names (common/GAssetDirs.pas, the Java clients' Assets). For
each path the root holds the bytes the most versions share; a version
with other bytes at that path keeps them in its own folder. A version
never sees a root file its install did not have.

--check DIR SRC unpacks nothing: it reads an extracted shared root DIR and
confirms that every version resolves every file of its install in SRC to
the same bytes, and sees no other file. The zip is deterministic (sorted
names, fixed times). Like graal-assets.zip it holds original Graal files:
it lives with Squirrel's project files and is never committed.
"""
import hashlib, os, sys, zipfile

# Folders a build reads after its own, as the code's labels have them
# (ClientAssetFolders / AssetLabel). The other folders are read alone.
CHAINS = {
    'b8': ['b7'],
    'b12': ['b11'], 'b13': ['b11'], 'b14': ['b11'], 'b15': ['b11'],
    '1.1.9': ['b15', 'b11'],
    '1.1': ['1.1.9', 'b15', 'b11'],
    '2.1t2': ['2.05r2'], '2.1t3': ['2.05r2'],
}

CLIENTS = '_clients'
FIXED = (1980, 1, 1, 0, 0, 0)


def walk(folder):
    """Every file under folder: relative path ('/' between folders) -> full path."""
    out = {}
    for d, dirs, files in os.walk(folder):
        dirs.sort()
        for f in sorted(files):
            full = os.path.join(d, f)
            out[os.path.relpath(full, folder).replace(os.sep, '/')] = full
    return out


def digest(path):
    with open(path, 'rb') as f:
        return hashlib.sha1(f.read()).hexdigest()


def installs(src, chains):
    """version -> {rel: full path}: its own folder, then its fallbacks."""
    folders = sorted(d for d in os.listdir(src)
                     if os.path.isdir(os.path.join(src, d)) and d != 'common')
    common = walk(os.path.join(src, 'common')) if os.path.isdir(os.path.join(src, 'common')) else {}
    raw = {v: walk(os.path.join(src, v)) for v in folders}
    out = {}
    for v in folders:
        seen = dict(common)
        for c in reversed([v] + chains.get(v, [])):
            seen.update(raw.get(c, {}))
        out[v] = seen
    return out


def plan(sets):
    """(root {rel: full}, overrides {version: {rel: full}}, allowed {version: [rel]})."""
    hashes = {}
    for files in sets.values():
        for full in files.values():
            if full not in hashes:
                hashes[full] = digest(full)
    # lower-case path -> (exact path, bytes) -> versions: a Windows folder
    # holds one file per lower-case name, and a case-sensitive file system
    # only finds the exact name, so both must match to share the root copy
    groups = {}
    for v in sorted(sets):
        for rel, full in sets[v].items():
            groups.setdefault(rel.lower(), {}).setdefault((rel, hashes[full]), []).append((v, full))
    root, over, allowed = {}, {v: {} for v in sets}, {v: [] for v in sets}
    for low in sorted(groups):
        cands = groups[low]
        best = max(sorted(cands), key=lambda k: len(cands[k]))
        rel = best[0]
        root[rel] = cands[best][0][1]
        for key, holders in cands.items():
            for v, full in holders:
                if key == best:
                    allowed[v].append(rel)
                else:
                    over[v][key[0]] = full
    return root, over, allowed


def readme(root, over, allowed, extra):
    rb = sum(os.path.getsize(f) for f in root.values())
    lines = [
        'Graal assets, one shared root',
        '=============================',
        '',
        'Extract this zip into the folder that holds the rebuilt programs',
        '(GraalB15.exe, Graal139.exe, Graal222.exe ...). Each program reads its',
        'own folder under _clients/ first, then only the files of this root',
        'that its own install had (_clients/<version>/files.txt). A real',
        'install still works: put it in a folder with no _clients/ in it.',
        '',
        'Root: %d files, %.1f MB.' % (len(root), rb / 1e6),
        '',
        '  %-14s %8s %9s %10s' % ('version', 'own', 'own MB', 'from root'),
    ]
    for v in sorted(over):
        ob = sum(os.path.getsize(f) for f in over[v].values())
        lines.append('  %-14s %8d %9.2f %10d' % (v, len(over[v]), ob / 1e6, len(allowed[v])))
    if extra:
        lines += ['', extra.rstrip('\n')]
    return '\n'.join(lines) + '\n'


def write_zip(out, root, over, allowed, text):
    entries = []
    for rel, full in root.items():
        entries.append((rel, full, None))
    for v in over:
        for rel, full in over[v].items():
            entries.append(('%s/%s/%s' % (CLIENTS, v, rel), full, None))
        entries.append(('%s/%s/files.txt' % (CLIENTS, v), None,
                        ''.join(r + '\n' for r in sorted(allowed[v]))))
    entries.append(('README-assets.txt', None, text))
    names = [e[0].lower() for e in entries]
    assert len(names) == len(set(names)), 'two entries share a name'
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for name, full, data in sorted(entries):
            info = zipfile.ZipInfo(name, FIXED)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            if data is None:
                with open(full, 'rb') as f:
                    data = f.read()
            z.writestr(info, data)


def check(folder, sets):
    """Resolve each version's install against an extracted shared root."""
    root_files = {r: f for r, f in walk(folder).items() if not r.startswith(CLIENTS + '/')}
    bad = 0
    for v in sorted(sets):
        own_dir = os.path.join(folder, CLIENTS, v)
        own = walk(own_dir) if os.path.isdir(own_dir) else {}
        own.pop('files.txt', None)
        allowed = set()
        if os.path.isfile(os.path.join(own_dir, 'files.txt')):
            with open(os.path.join(own_dir, 'files.txt'), encoding='utf-8') as f:
                allowed = {l.strip().lower() for l in f if l.strip()}
        seen = dict((r.lower(), f) for r, f in root_files.items() if r.lower() in allowed)
        seen.update((r.lower(), f) for r, f in own.items())
        want = {r.lower(): f for r, f in sets[v].items()}
        missing = [r for r in want if r not in seen]
        extra = [r for r in seen if r not in want]
        differ = [r for r in want if r in seen and digest(seen[r]) != digest(want[r])]
        # the exact name must exist where the case matters
        case = [r for r in sets[v] if r.lower() in seen and
                not seen[r.lower()].replace(os.sep, '/').endswith('/' + r)]
        if missing or extra or differ or case:
            bad += 1
            print('%s: %d missing, %d extra, %d differ, %d case' %
                  (v, len(missing), len(extra), len(differ), len(case)))
            for r in (missing + extra + differ + case)[:5]:
                print('   ', r)
    print('%d versions checked, %d wrong' % (len(sets), bad))
    return bad == 0


def main(argv):
    chains = {k: list(v) for k, v in CHAINS.items()}
    args, readme_file, check_dir = [], None, None
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == '--chain':
            v, _, rest = argv[i + 1].partition('=')
            chains[v] = [c for c in rest.split(';') if c]
            i += 2
        elif a == '--readme':
            readme_file = argv[i + 1]
            i += 2
        elif a == '--check':
            check_dir = argv[i + 1]
            i += 2
        else:
            args.append(a)
            i += 1
    if check_dir is not None:
        if len(args) != 1:
            sys.exit(__doc__)
        return 0 if check(check_dir, installs(args[0], chains)) else 1
    if len(args) != 2:
        sys.exit(__doc__)
    src, out = args
    sets = installs(src, chains)
    root, over, allowed = plan(sets)
    extra = open(readme_file, encoding='utf-8').read() if readme_file else ''
    write_zip(out, root, over, allowed, readme(root, over, allowed, extra))
    before = sum(os.path.getsize(f) for v in os.listdir(src)
                 for f in walk(os.path.join(src, v)).values()
                 if os.path.isdir(os.path.join(src, v)))
    rb = sum(os.path.getsize(f) for f in root.values())
    ob = sum(os.path.getsize(f) for o in over.values() for f in o.values())
    print('%s: root %d files %.1f MB, own folders %d files %.1f MB '
          '(the per-version folders held %.1f MB), zip %.1f MB' %
          (out, len(root), rb / 1e6, sum(len(o) for o in over.values()), ob / 1e6,
           before / 1e6, os.path.getsize(out) / 1e6))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
