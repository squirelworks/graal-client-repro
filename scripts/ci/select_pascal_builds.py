"""Select Pascal CI folders; shared code and CI changes retain full coverage.

Dedicated host workflows are not evidence of coverage for arbitrary Torque
files. Until delegated coverage is verified, all shared paths fail closed.
"""
from pathlib import Path
import sys


def select_builds(paths, available):
    available = sorted(set(available))
    selected = set()
    for path in paths:
        path = path.strip()
        if not path or path.endswith('.md'):
            continue
        if path.startswith(('common/', 'scripts/', '.github/workflows/')):
            return available
        folder = path.split('/', 1)[0]
        if folder in available:
            selected.add(folder)
    return sorted(selected)


if __name__ == '__main__':
    repo = Path(__file__).resolve().parents[2]
    available = [p.name for p in repo.glob('graal-*')
                 if (p / 'src').is_dir() and not p.name.startswith('graal-3d-')]
    print(' '.join(select_builds(sys.stdin, available)))
