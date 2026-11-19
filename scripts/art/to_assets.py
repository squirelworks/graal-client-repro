#!/usr/bin/env python3
"""Copy a program's own resources into an assets/ folder, to be shown in
place of graal-delphi's art.

    python3 -I scripts/art/to_assets.py REAL/Graal.exe ASSETS_DIR [VERSION]

Writes every RCDATA resource of the program you own (start art, picture
buttons, forms, Training levels) to ASSETS_DIR/<VERSION>/res/<NAME><ext>
(ASSETS_DIR/res/ without VERSION), named as the rebuild asks for them
(SCREENIMG1.jpg, BUTTON1.bmp, TCONNECTFRAME.dfm, TUTORIALA1.graal). Put
ASSETS_DIR beside the rebuilt program as `assets/` (docs/assets.md, "Your
own files"). VERSION is the build's label (2.31, 2.05r2, b9, ...).

The program is only read. The files written are the program's owner's:
keep them out of the repository.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), 'realres'))
from extract_res import PE  # noqa: E402


def ext_of(d, name):
    if d[:4] == b'TPF0':
        return '.dfm'
    if d[:2] == b'\xff\xd8':
        return '.jpg'
    if d[:2] == b'BM':
        return '.bmp'
    if d[:4] == b'\x89PNG':
        return '.png'
    if d[:3] == b'GIF':
        return '.gif'
    if d[:4] in (b'GR-V', b'Z3-V') or d[:8] == b'GLEVNW01':
        return '.graal' if d[:2] != b'GL' else '.nw'
    return '.bin'


def main():
    if len(sys.argv) not in (3, 4):
        print(__doc__)
        sys.exit(64)
    exe, out = sys.argv[1], sys.argv[2]
    ver = sys.argv[3] if len(sys.argv) == 4 else ''
    dest = os.path.join(out, ver, 'res') if ver else os.path.join(out, 'res')
    os.makedirs(dest, exist_ok=True)
    n = 0
    for t, name, lang, d in PE(open(exe, 'rb').read()).resources():
        if t != 10 or not isinstance(name, str) or name in ('DVCLAL', 'PACKAGEINFO'):
            continue
        p = os.path.join(dest, name.upper() + ext_of(d, name))
        if os.path.exists(p):
            continue
        with open(p, 'wb') as f:
            f.write(d)
        n += 1
    print('%d resources in %s' % (n, dest))


if __name__ == '__main__':
    main()
