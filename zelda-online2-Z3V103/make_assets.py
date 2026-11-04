#!/usr/bin/env python3
"""Make the assets zip for the Zelda Online 2 rebuild from your own copy.

  make_assets.py SRC OUT.zip

SRC is an unpacked Zelda Online 2 (the package, or its game/ folder; the
levels are found anywhere under it). The zip gets only what the rebuild reads, and nothing else:

  graal-assets/zelda-online2/pics1.gif      the tile sheet
  graal-assets/zelda-online2/arrays.dat     tile types
  graal-assets/zelda-online2/levels/*.zelda every level

Unzip it next to ZeldaOnline2.jar. Class files, sources and pages are never
copied. The zip is your own files: it is not part of this repository.
"""
import os
import sys
import zipfile

LABEL = 'zelda-online2'
TOP = {'pics1.gif', 'arrays.dat'}


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    src, out = sys.argv[1], sys.argv[2]
    picked = {}
    for d, _, names in os.walk(src):
        for n in sorted(names):
            low = n.lower()
            p = os.path.join(d, n)
            if low in TOP:
                picked.setdefault(low, p)
            elif low.endswith('.zelda'):
                picked.setdefault('levels/' + low, p)
    missing = [n for n in sorted(TOP) if n not in picked]
    if missing:
        print('not found in SRC (the built-in stand-ins are used instead):', ', '.join(missing))
    root = 'graal-assets/' + LABEL + '/'
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for rel in sorted(picked):
            z.write(picked[rel], root + rel)
    print('%s: %d files' % (out, len(picked)))


if __name__ == '__main__':
    main()
