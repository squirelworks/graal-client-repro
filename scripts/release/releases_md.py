#!/usr/bin/env python3
"""Point RELEASES.md at a new release of some clients.

    python3 -I scripts/release/releases_md.py v0.0.3 graal-2.05r2-GNW03081 ...

RELEASES.md has one row per client with its newest release. For each
folder named, this rewrites that row's Level, Release and Download cells to
the given version. Every client of a version is in ONE release, tagged
with the version itself (v0.0.4), and each zip is named
<folder>-<version>[-os].zip, so the links follow from it. Rows of clients not named are
left alone, so the table stays "the newest release of each client". It also
moves the snapshot date to today. Does nothing if there is no RELEASES.md.
"""
import datetime
import os
import re
import sys

BASE = 'https://github.com/squirelworks/graal-delphi/releases'


def update(text, version, folders, today):
    level = version[1:] if version.startswith('v') else version
    out = []
    done = set()
    for line in text.split('\n'):
        for f in folders:
            if line.startswith('|') and f'[`{f}`]' in line:
                cells = line.split('|')
                # | Client | Folder | Token | Rebuilt from | Level | Release | Download | Notes |
                if len(cells) >= 9:
                    cells[5] = f' {level} '
                    cells[6] = f' [{version}]({BASE}/tag/{version}) '
                    cells[7] = re.sub(r'/download/[^/)]+/' + re.escape(f) + r'-v[0-9]+(?:\.[0-9]+)*',
                                      f'/download/{version}/{f}-{version}', cells[7])
                    line = '|'.join(cells)
                    done.add(f)
                break
        out.append(line)
    text = '\n'.join(out)
    # the Level key names every level the table uses
    out = []
    for line in text.split('\n'):
        if line.startswith('**Level**') and not re.search(r' ' + re.escape(level) + r'[ :]', line):
            line = line.rstrip() + f' {level}: every client released together; see its release notes.'
        out.append(line)
    text = '\n'.join(out)
    text = re.sub(r'(snapshot taken from the GitHub releases API on )\d{4}-\d{2}-\d{2}',
                  r'\g<1>' + today, text)
    return text, done


def main():
    version, folders = sys.argv[1], sys.argv[2:]
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'RELEASES.md')
    if not os.path.exists(path):
        print('no RELEASES.md; nothing to update')
        return 0
    with open(path, encoding='utf-8') as f:
        text = f.read()
    text, done = update(text, version, folders, datetime.date.today().isoformat())
    with open(path, 'w', encoding='utf-8') as f:
        f.write(text)
    missing = sorted(set(folders) - done)
    print(f'RELEASES.md: {len(done)} rows now at {version}')
    if missing:
        print('no row for: ' + ' '.join(missing))
    return 0


if __name__ == '__main__':
    sys.exit(main())
