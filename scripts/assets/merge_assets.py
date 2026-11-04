#!/usr/bin/env python3
"""Merge per-version Graal asset sets into one graal-assets folder.

  merge_assets.py OUT VERSION=DIR [VERSION=DIR ...]

Each DIR holds one version's files laid out as they sit next to that
version's EXE. A file goes to OUT/common/ only when EVERY set has it, byte
for byte, at the same path; everything else goes to OUT/<VERSION>/. Every
build reads common/, so a file shared by only some sets must stay in their
own folders: in common/ it would hand the other builds a file their
install never had. The rebuilt clients look in their version folder, then in
common/ (common/GAssetDirs.pas). The output is the player's own Graal
files: it is never committed.
"""
import hashlib, os, shutil, sys

SKIP_EXT = {'.exe', '.dll'}
SKIP_NAMES = {'graalconfig.txt'}
# the sets' own notes; the merged folder gets one README
SKIP_TOP = {'readme-assets.txt', 'readme.txt'}


def files(root):
    for d, _, names in os.walk(root):
        for n in names:
            p = os.path.join(d, n)
            rel = os.path.relpath(p, root).replace(os.sep, '/')
            if os.path.splitext(n)[1].lower() in SKIP_EXT or n.lower() in SKIP_NAMES:
                continue
            if '/' not in rel and n.lower() in SKIP_TOP:
                continue
            yield rel, p


def digest(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for b in iter(lambda: f.read(1 << 16), b''):
            h.update(b)
    return h.hexdigest()


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    out = sys.argv[1]
    sets = [a.split('=', 1) for a in sys.argv[2:]]
    seen = {}  # rel (lower) -> list of (version, path, hash, rel)
    for ver, root in sets:
        for rel, p in files(root):
            seen.setdefault(rel.lower(), []).append((ver, p, digest(p), rel))
    counts = {'common': 0}
    for key, entries in sorted(seen.items()):
        hashes = {e[2] for e in entries}
        if len(sets) >= 2 and len(entries) == len(sets) and len(hashes) == 1:
            dests = [('common', entries[0])]
        else:
            dests = [(e[0], e) for e in entries]
        for folder, (ver, p, _, rel) in dests:
            dst = os.path.join(out, folder, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy2(p, dst)
            counts[folder] = counts.get(folder, 0) + 1
    for k, v in sorted(counts.items()):
        print(f'{k}: {v} files')


if __name__ == '__main__':
    main()
