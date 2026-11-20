#!/usr/bin/env python3
"""The notes of the one release that holds every client of a version.

    python3 -I scripts/release/combined_notes.py v0.0.4 graal-b1-19980906 ... > notes.md

Every client of a version goes out in ONE GitHub release, tagged with the
version (v0.0.4). Its text is a short common header, then one section per
folder named: the first heading of the folder's RELEASE_NOTES.md, the
names of that folder's zips, and the folder's "What's new in <version>"
section. RELEASE, if set, names the release in the header when it is not
the version itself (v0.0.3r1 holds the v0.0.3 zips). Folders come in build
date order, oldest first (build_date), which also puts them in version
order. Each folder is labelled with how faithful its rebuild is (track).

GitHub refuses release notes over 125,000 characters. When the full text
would pass LIMIT, each folder gets one line instead: its title, a link to
its "What's new" section in its RELEASE_NOTES.md at the tag, and how many
zips it has (GitHub lists the zips under Assets anyway).
"""
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
REPO = 'https://github.com/squirelworks/graal-client-repro'
LIMIT = 120000  # GitHub's cap is 125,000; keep a margin

HEADER = """Every Graal client rebuilt in graal-delphi, released together at {release}. \
Each client's zip is attached below and named after its folder: \
`<folder>-{version}-windows.zip` is the Windows program, `-linux.zip` the Linux one, and `-macos-arm64.zip` / `-macos-x86_64.zip` the macOS ones (Apple silicon / Intel; headless for now, where the build worked). \
[RELEASES.md]({repo}/blob/main/RELEASES.md) has one row per client with what it is and a direct download link.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

The zips hold no original Graal code, graphics, sounds or levels. Each \
program carries small stand-in graphics and a starter level of its own, so \
it runs as it is; put it in a folder with your own copy of that build's \
files and they take their place.

On Windows the first start may show **"Windows protected your PC"**: that \
is SmartScreen meeting an unsigned program. Click **More info**, then \
**Run anyway**, or unblock the zip before extracting it (right-click, \
**Properties**, tick **Unblock**). See \
[the README]({repo}#windows-says-windows-protected-your-pc).

## The clients

Oldest build first. Each client says how faithful its rebuild is: \
**faithful engine** means the program starts a rebuild of the original's own \
engine (Torque for early 3.x, Quattro for late 5.x and 6.x); **like the \
original** means the original was written in that language too (Delphi up \
to 2.31, Java, C); **Delphi stand-in** means a Delphi program plays the \
build until its engine is finished \
([docs/engine-repro-policy.md]({repo}/blob/main/docs/engine-repro-policy.md)).
"""


# Build dates for folders whose name carries neither a date nor a dated
# token. Sources: Graal_analysis client-internals/build-catalogue.md (link
# or disk-set date); where only the year or month is known, the first of it.
BUILD_DATES = {
    'graal-1.21-GSERV007': '1999-05-10',
    'graal-1.25-GSERV009': '1999-08-07',
    'graal-1.27-GSERV011': '1999-10-23',
    'graal-1.28b2-GSERV013': '1999-11-23',
    'graal-1.3test-GSERV014': '1999-11-29',
    'graal-1.31-GSERV016': '1999-12-07',
    'graal-1.32-GSERV018': '2000-01-12',
    'graal-39ster-1.00': '2014-04-01',
    'graalgb-1.10': '1999-12-01',
    'javagraal-2000': '2000-07-01',
    'zelda-online1-Z3V102': '1998-05-01',
    'zelda-online2-Z3V103': '1998-07-01',
    # No build stamp; the connector token GNP1905C is not a build date.
    # Placed after 6.03r7 (November 2012), the last stamped 6.0x build.
    'graal-6.1.1.3-GNP1905C': '2012-12-01',
    'graal-6.11r1-mac': '2012-12-02',
}


def build_date(folder):
    """'YYYY-MM-DD' for a folder: BUILD_DATES, else the YYYYMMDD date in
    its name, else the date stamp of its token (DDMMY; Y is the last digit
    of the year up to 2009 and a hex digit from 2010, Graal_analysis
    protocol/login-tokens-3x-7x.md; a G3D 0 is 2010), else '9999' (last)."""
    if folder in BUILD_DATES:
        return BUILD_DATES[folder]
    m = re.search(r'-((?:19|20)\d\d)(\d\d)(\d\d)(?:-|$)', folder)
    if m:
        return '-'.join(m.groups())
    m = re.search(r'-(GNW|G2N|G3D)(\d\d)(\d\d)([0-9A-F])$', folder)
    if m:
        kind, day, month, y = m.groups()
        year = 2000 + int(y, 16)
        if kind == 'G3D' and y == '0':
            year = 2010
        return f'{year}-{month}-{day}'
    return '9999'


def version_key(folder):
    """Numbers in the folder's version part, to break ties between folders
    with the same date (2.05, 2.05r1, 2.05r2)."""
    return [int(n) for n in re.findall(r'\d+', folder.split('-')[1])] if '-' in folder else []


ORIGINAL_DELPHI = re.compile(r'^graal-(b\d|1\.|2\.|nm|nwb|x-|3d-)')


def track(folder):
    """How faithful the rebuild is: the folder README's Repro tracks
    default, else the language the original was written in."""
    try:
        with open(os.path.join(ROOT, folder, 'README.md'), encoding='utf-8') as fh:
            readme = fh.read()
    except OSError:
        readme = ''
    m = re.search(r'^- \*\*default:\*\*(.*)$', readme, re.M)
    if m:
        if 'stand-in' in m.group(1):
            return 'Delphi stand-in (its engine is still being wired)'
        return 'faithful engine'
    if folder.startswith(('zelda-online', 'javagraal')):
        return 'Java, like the original'
    if folder.startswith('graalgb'):
        return 'C (GBDK), like the original'
    if ORIGINAL_DELPHI.match(folder):
        return 'Delphi, like the original'
    return 'Delphi stand-in'


def section(text, version):
    """The bullets under '## What's new in <version>', or '' if none."""
    m = re.search(r"^## What's new in " + re.escape(version) + r"\s*$(.*?)(?=^## |\Z)",
                  text, re.M | re.S)
    return m.group(1).strip() if m else ''


def anchor(heading):
    """GitHub's anchor for a Markdown heading."""
    a = re.sub(r'[^\w\- ]', '', heading.strip().lower())
    return a.replace(' ', '-')


def compact(version, folders, zips):
    out = [HEADER.format(version=version, release=os.environ.get('RELEASE') or version, repo=REPO),
           "Each client's changes are in its folder's RELEASE_NOTES.md (the notes "
           "for every client together are too long for one GitHub release).\n"]
    frag = anchor(f"What's new in {version}")
    for f in folders:
        with open(os.path.join(ROOT, f, 'RELEASE_NOTES.md'), encoding='utf-8') as fh:
            text = fh.read()
        title = text.split('\n', 1)[0].lstrip('# ').strip()
        n = len([z for z in zips if z.startswith(f'{f}-{version}')])
        line = f'- **{title}** (`{f}`, {build_date(f)}), {track(f)}'
        if section(text, version):
            line += f': [what\'s new]({REPO}/blob/{version}/{f}/RELEASE_NOTES.md#{frag})'
        if n:
            line += f', {n} zip' + ('s' if n != 1 else '')
        out.append(line)
    return '\n'.join(out) + '\n'


def notes(version, folders, zips):
    full = full_notes(version, folders, zips)
    return full if len(full) <= LIMIT else compact(version, folders, zips)


def full_notes(version, folders, zips):
    out = [HEADER.format(version=version, release=os.environ.get('RELEASE') or version, repo=REPO)]
    for f in folders:
        with open(os.path.join(ROOT, f, 'RELEASE_NOTES.md'), encoding='utf-8') as fh:
            text = fh.read()
        title = text.split('\n', 1)[0].lstrip('# ').strip()
        out.append(f'### {title} (`{f}`)\n')
        out.append(f'Built {build_date(f)}. Rebuild: {track(f)}.\n')
        mine = [z for z in zips if z.startswith(f'{f}-{version}')]
        if mine:
            out.append('Download: ' + ', '.join(f'`{z}`' for z in sorted(mine)) + '\n')
        new = section(text, version)
        if new:
            out.append(new + '\n')
    return '\n'.join(out)


def main():
    if len(sys.argv) < 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    version, folders = sys.argv[1], sys.argv[2:]
    folders.sort(key=lambda f: (build_date(f), version_key(f), f))
    # ZIPS: the release's zip file names, space-separated (optional)
    zips = [os.path.basename(z) for z in os.environ.get('ZIPS', '').split()]
    sys.stdout.write(notes(version, folders, zips))
    return 0


if __name__ == '__main__':
    sys.exit(main())
