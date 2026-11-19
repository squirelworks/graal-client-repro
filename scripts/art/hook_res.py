#!/usr/bin/env python3
"""Puts the assets/ override in front of every compiled-in resource.

    python3 -I scripts/art/hook_res.py            patch the units
    python3 -I scripts/art/hook_res.py --check    exit 1 if one lacks it

Each unit that hands out a build's compiled-in resources (src/Res*.pas,
src/RealRes*.pas, ResGraal*.pas) first asks GAssetDirs.UserResource for
the player's own copy in assets/ (docs/assets.md, "Your own files"). The
generators write the same lines (scripts/res/make_resunit.py,
scripts/res/extract_1x.py, scripts/res20x/make_res20x.py,
scripts/realres/extract_res.py, scripts/builtin/make_res222.py); this
script brings units made before them up to date, and is a no-op after.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import containers as C  # noqa: E402

MARK = 'UserResource('
HOOK = ("  { the player's own copy in assets/ wins (docs/assets.md) }\n"
        "  if UserResource(Name, Data) then begin Result := True; Exit; end;\n")
ACCESSORS = ('ResFile', 'ExeResource', 'RealResource', 'EmbeddedRes')


def hook_text(text):
    impl = text.find('\nimplementation')
    if impl < 0:
        return text
    head, body = text[:impl], text[impl:]
    changed = False
    for fn in ACCESSORS:
        m = re.search(r'\nfunction %s\(const Name: string; out Data: string\): Boolean;\n' % fn, body)
        if not m:
            continue
        b = body.find('\nbegin\n', m.end() - 1)
        if b < 0:
            continue
        nxt = body[b + 7:b + 7 + 300]
        if MARK in nxt:
            continue
        body = body[:b + 7] + HOOK + body[b + 7:]
        changed = True
    # extract_1x units: function ResConnectFrame: string; ... (fixed names)
    rc = {'OnlineStart': 'ONLINESTARTLEVEL', 'Characters': 'HEADSCONFIG'}

    def one(m):
        k = m.group(1)
        if k in rc:
            return ("\nfunction Res%s: string;\nbegin\n"
                    "  { the player's own copy in assets/ wins (docs/assets.md) }\n"
                    "  if UserResource('%s', Result) or UserResource('%s', Result) then Exit;\n" % (k, rc[k], k))
        return ("\nfunction Res%s: string;\nbegin\n"
                "  { the player's own copy in assets/ wins (docs/assets.md) }\n"
                "  if UserResource('T%s', Result) or UserResource('%s', Result) then Exit;\n" % (k, k.upper(), k))
    nb = re.sub(r"\nfunction Res([A-Za-z]+): string;\nbegin\n(?!  \{ the player)", one, body)
    if nb != body:
        body = nb
        changed = True
    if not changed:
        return text
    # GAssetDirs in the implementation's uses clause
    m = re.match(r'\nimplementation\n\n?uses\n', body)
    if m:
        if 'GAssetDirs' not in body[:400]:
            body = body[:m.end()] + '  GAssetDirs,\n' + body[m.end():]
    else:
        body = body.replace('\nimplementation\n', '\nimplementation\n\nuses\n  GAssetDirs;\n', 1)
    return head + body


def units():
    for kind, path in C.containers():
        if kind == 'pas' and path != 'common/GRes20x.pas':
            yield path


def main():
    check = sys.argv[1:] == ['--check']
    bad = []
    for p in units():
        full = os.path.join(C.ROOT, p)
        t = open(full, encoding='latin1').read()
        nt = hook_text(t)
        if nt != t:
            bad.append(p)
            if not check:
                open(full, 'w', encoding='latin1', newline='').write(nt)
    for p in bad:
        print(('lacks the assets/ hook: ' if check else 'hooked: ') + p)
    if check and bad:
        sys.exit(1)


if __name__ == '__main__':
    main()


def hook_file(path):
    """Hook one unit a generator has just written (the generators call this)."""
    t = open(path, encoding='latin1').read()
    nt = hook_text(t)
    if nt != t:
        open(path, 'w', encoding='latin1', newline='').write(nt)
    print('note: run scripts/art/make_art.py before committing; resources taken '
          'from a real program are replaced by graal-delphi\'s own art there, and '
          'the originals belong in assets/ (docs/assets.md)')
