#!/usr/bin/env python3
"""Make the assets zip for the Java Graal rebuild from your own copy.

  make_assets.py SRC OUT.zip

SRC is your copy of the Java Graal files (the folder that held Graal.jar,
its GIFs and levels/). The zip gets only what the rebuild reads:

  graal-assets/javagraal/pics1.gif, sprites.gif, letters.gif, arrays.dat
  graal-assets/javagraal/levels/...   levels (.graal, .zelda), the GIFs the
                                      levels show, and sounds (.wav)

Unzip it next to JavaGraal.jar. Jars, class files and web pages are never
copied. The zip is your own files: it is not part of this repository.
"""
import os
import sys
import zipfile

LABEL = 'javagraal'
TOP = {'pics1.gif', 'sprites.gif', 'letters.gif', 'arrays.dat'}
LEVEL_EXT = {'.graal', '.zelda', '.gif', '.wav'}


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    src, out = sys.argv[1], sys.argv[2]
    picked = {}
    for d, _, names in os.walk(src):
        rel_dir = os.path.relpath(d, src).replace(os.sep, '/')
        parts = rel_dir.lower().split('/')
        in_levels = 'levels' in parts
        for n in sorted(names):
            low = n.lower()
            p = os.path.join(d, n)
            if low in TOP and not in_levels:
                picked.setdefault(low, p)
            elif in_levels and os.path.splitext(low)[1] in LEVEL_EXT:
                sub = '/'.join(rel_dir.split('/')[parts.index('levels') + 1:])
                picked.setdefault('levels/' + (sub + '/' if sub else '') + n, p)
    missing = [n for n in sorted(TOP) if n not in picked]
    if missing:
        print('not found in SRC (stand-ins are used instead):', ', '.join(missing))
    root = 'graal-assets/' + LABEL + '/'
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for rel in sorted(picked):
            z.write(picked[rel], root + rel)
    print('%s: %d files' % (out, len(picked)))


if __name__ == '__main__':
    main()
