#!/usr/bin/env python3
"""The notes of the one release that holds every client of a version.

    python3 -I scripts/release/combined_notes.py v0.0.4 graal-b1-19980906 ... > notes.md

Every client of a version goes out in ONE GitHub release, tagged with the
version (v0.0.4). Its text is a short common header, then one section per
folder named: the first heading of the folder's RELEASE_NOTES.md, the
names of that folder's zips, and the folder's "What's new in <version>"
section. RELEASE, if set, names the release in the header when it is not
the version itself (v0.0.3r1 holds the v0.0.3 zips). Folders come in RELEASES.md's order (by era, oldest first), any
it does not list after them.
"""
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
REPO = 'https://github.com/squirelworks/graal-client-repro'

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
"""


def section(text, version):
    """The bullets under '## What's new in <version>', or '' if none."""
    m = re.search(r"^## What's new in " + re.escape(version) + r"\s*$(.*?)(?=^## |\Z)",
                  text, re.M | re.S)
    return m.group(1).strip() if m else ''


def notes(version, folders, zips):
    out = [HEADER.format(version=version, release=os.environ.get('RELEASE') or version, repo=REPO)]
    for f in folders:
        with open(os.path.join(ROOT, f, 'RELEASE_NOTES.md'), encoding='utf-8') as fh:
            text = fh.read()
        title = text.split('\n', 1)[0].lstrip('# ').strip()
        out.append(f'### {title} (`{f}`)\n')
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
    try:
        with open(os.path.join(ROOT, 'RELEASES.md'), encoding='utf-8') as fh:
            table = fh.read()
    except OSError:
        table = ''
    pos = {f: table.find(f'[`{f}`]') for f in folders}
    folders.sort(key=lambda f: (pos[f] < 0, pos[f]))
    # ZIPS: the release's zip file names, space-separated (optional)
    zips = [os.path.basename(z) for z in os.environ.get('ZIPS', '').split()]
    sys.stdout.write(notes(version, folders, zips))
    return 0


if __name__ == '__main__':
    sys.exit(main())
