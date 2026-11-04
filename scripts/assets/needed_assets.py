#!/usr/bin/env python3
"""Cut a graal-assets folder down to the files the rebuilt clients open,
and pack it as graal-assets.zip.

  needed_assets.py SRC OUT.zip [--readme FILE] [--list CUT.txt]
                   [--fallback VERSION=OTHER ...]

SRC is a graal-assets folder (common/ and one folder per version, as
merge_assets.py writes it). A file is kept when a rebuilt client can open
it (docs/assets.md has the reasons):

  - anything under levels/, sounds/ or maps/: levels, ganis, heads,
    bodies, swords, shields, hats, weapons, images, midis and sounds are
    looked up by the name a level, script or server gives, and a name may
    carry a sub folder (levels/ is searched with the name as given);
  - in the version folder itself, the files the code names (tile sheets,
    arrays, sprites, the default player pictures and weapons) and the map
    grids with their pictures (bigmap.txt, setmap names);
  - the start-window background and buttons the start screens open
    (embedded/images/screenimg1.jpg, button1.bmp, button2.bmp);
  - 3.04's and 4.x's license/license.graal (their listserver);
  - for the 1998-99 betas (b1 .. b15): arrays.dat, and the level files
    and pictures in levels/ and next to the exe, where those installs
    kept them (no sound or music: the beta builds play none);
  - for Graal3D (3d): the 20 meshes and textures its build opens.

--fallback VERSION=OTHER is for a build whose label reads OTHER's folder
after its own (e.g. 'b12;b11'): VERSION's kept files that OTHER has byte
for byte at the same path are left out of VERSION's folder. It is refused
unless every kept file of OTHER is also in VERSION's install, so a
fallback never hands a build a file its own install did not have.

Everything else is cut: readmes, release notes, help files, language
files, fonts, the rest of the resources taken out of the exe, the editor's
new-level template and object sets of builds with no editor. CUT.txt
lists what was left out. The zip is deterministic (sorted, fixed times),
extracts as graal-assets/, and is never committed.
"""
import fnmatch, os, re, sys, zipfile

KEEP_DIRS = ('levels/', 'sounds/', 'maps/')

# files at the top of a version folder that the code opens by name
KEEP_TOP = [
    'pics1.png', 'pics1.gif', 'picso.png', 'sprites.png', 'state.png',
    'letters.png', 'bomb1.png', 'bomb2.png', 'body.png',
    'head0.png', 'head0.gif', 'sword1.png', 'sword1.gif',
    'shield1.png', 'shield1.gif', 'wbow*.gif', 'wbow*.png',
    'wbomb*.gif', 'wbomb*.png', 'baddy*.gif',
    'arrays.dat', 'arrays2.dat', 'objects.dat', 'listserver.txt',
    'start.nw', 'start2.nw',
    # map grids (setmap / the M key) and their pictures
    'bigmap.txt', 'minimap.txt', 'map.png', 'map2.png',
    'tutorialmap.txt', 'tutorialmap.png', 'tutorialmap2.png',
]

# start-window art taken out of the exes, opened by the start screens
KEEP_PATHS = {
    'embedded/images/screenimg1.jpg',
    'embedded/images/button1.bmp',
    'embedded/images/button2.bmp',
    # 3.04: the listserver host and port
    'license/license.graal',
}

# builds with an editor of its own (objects.dat): the others cut it
EDITOR_VERSIONS = {'2.05r2', '2.17.1'}


def is_map_grid(path):
    """A level-name grid as the map code reads it: a comma list of quoted
    level names."""
    try:
        with open(path, 'rb') as f:
            head = f.read(200)
    except OSError:
        return False
    return head.startswith(b'"') and (b'.graal"' in head or b'.nw"' in head)


# The 1998-99 betas (b1 .. b15, b4a, b5a, b9a): their installs keep levels
# and the pictures levels name next to the exe, and the builds look a name
# up in the folder itself and in levels/ (FindFile(Name, ['', 'levels/'])).
# They play no sound and have no editor.
BETA = re.compile(r'^b\d+a?$')
BETA_LEVEL_EXT = ('.graal', '.zelda', '.editor', '.editor1', '.forest')
BETA_IMAGE_EXT = ('.gif', '.png')


def keep_beta(low):
    # levels and pictures only, in levels/ or next to the exe: the betas
    # open no sound or music (.wav, .mid) and no .lost files
    if '/' in low and not low.startswith('levels/'):
        return False
    return low == 'arrays.dat' or low.endswith(BETA_LEVEL_EXT + BETA_IMAGE_EXT)


# Graal3D (2000): the meshes and textures its build opens (startlevel.x
# is the server's; graal3dconfig.txt is settings, left to the player)
GRAAL3D = {
    'level1.x', 'body.x', 'head.x', 'armleft.x', 'armright.x', 'handleft.x',
    'handright.x', 'footleft.x', 'footright.x', 'body.bmp', 'body1.bmp',
    'man.bmp', 'grass.bmp', 'way.bmp', 'stones.bmp', 'wall.bmp', 'tower.bmp',
    'platform.bmp', 'clouds.bmp', 'logo.bmp',
}


def keep(version, rel, full, folder):
    low = rel.lower()
    if os.path.basename(low) == 'thumbs.db':
        return False  # Windows Explorer's thumbnail cache, never opened
    if version == '3d':
        return low in GRAAL3D
    if BETA.match(version):
        return keep_beta(low)
    if low.startswith(KEEP_DIRS) or low in KEEP_PATHS:
        return True
    if '/' in low:
        return False
    if low == 'objects.dat' and version not in EDITOR_VERSIONS:
        return False
    if any(fnmatch.fnmatch(low, p) for p in KEEP_TOP):
        return True
    base, ext = os.path.splitext(low)
    if ext == '.txt' and is_map_grid(full):
        return True
    # a picture whose name starts with a map grid's name (mappw.png,
    # mapmantara2.png, ccbig.gif)
    if ext in ('.png', '.gif'):
        for n in os.listdir(folder):
            b, e = os.path.splitext(n.lower())
            if e == '.txt' and base.startswith(b) and is_map_grid(os.path.join(folder, n)):
                return True
    return False


def digest(path):
    import hashlib
    with open(path, 'rb') as f:
        return hashlib.sha256(f.read()).hexdigest()


def apply_fallbacks(kept, fallbacks):
    """Leave out of VERSION's folder what its fallback has byte for byte."""
    if not fallbacks:
        return kept, []
    by_version = {}
    for name, full in kept:
        v, rel = name.split('/', 1)
        by_version.setdefault(v, {})[rel.lower()] = full
    drop = set()
    for v, o in fallbacks.items():
        own, other = by_version.get(v, {}), by_version.get(o, {})
        if o in fallbacks:
            sys.exit('--fallback %s=%s: %s has a fallback itself' % (v, o, o))
        extra = sorted(set(other) - set(own))
        if extra:
            sys.exit('--fallback %s=%s refused: %s has %d files %s lacks, e.g. %s'
                     % (v, o, o, len(extra), v, extra[0]))
        for rel, full in own.items():
            if rel in other and digest(full) == digest(other[rel]):
                drop.add((v, rel))
    out, shared = [], []
    for name, full in kept:
        v, rel = name.split('/', 1)
        (shared if (v, rel.lower()) in drop else out).append((name, full))
    return out, shared


def main():
    args = sys.argv[1:]
    if len(args) < 2:
        sys.exit(__doc__)
    src, out = args[0], args[1]
    readme = cut_list = None
    if '--readme' in args:
        readme = args[args.index('--readme') + 1]
    if '--list' in args:
        cut_list = args[args.index('--list') + 1]
    fallbacks = {}
    for i, a in enumerate(args):
        if a == '--fallback':
            v, o = args[i + 1].split('=', 1)
            fallbacks[v] = o
    kept, cut = [], []
    for top in sorted(os.listdir(src)):
        tp = os.path.join(src, top)
        if not os.path.isdir(tp):
            continue
        for d, dirs, names in os.walk(tp):
            dirs.sort()
            for n in sorted(names):
                full = os.path.join(d, n)
                rel = os.path.relpath(full, tp).replace(os.sep, '/')
                (kept if keep(top, rel, full, tp) else cut).append((top + '/' + rel, full))
    kept, shared = apply_fallbacks(kept, fallbacks)
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        def add(name, data):
            zi = zipfile.ZipInfo('graal-assets/' + name, (2000, 1, 1, 0, 0, 0))
            zi.compress_type = zipfile.ZIP_DEFLATED
            zi.external_attr = 0o644 << 16
            z.writestr(zi, data)
        if readme:
            with open(readme, 'rb') as f:
                add('README.txt', f.read())
        for name, full in sorted(kept):
            with open(full, 'rb') as f:
                add(name, f.read())
    if cut_list:
        with open(cut_list, 'w', encoding='utf-8') as f:
            for name, full in sorted(cut):
                f.write('%9d %s\n' % (os.path.getsize(full), name))
    print('kept %d files (%d bytes), cut %d files (%d bytes), '
          'read through a fallback %d files (%d bytes)' % (
        len(kept), sum(os.path.getsize(p) for _, p in kept),
        len(cut), sum(os.path.getsize(p) for _, p in cut),
        len(shared), sum(os.path.getsize(p) for _, p in shared)))


if __name__ == '__main__':
    main()
