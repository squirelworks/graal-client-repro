"""Select Pascal CI folders from changed paths; C++ host tests own Torque slices."""
from pathlib import Path
import sys

HOST_TESTS = {'scripts/tests/host_script_selection.py'}

def select_builds(paths, available, cpp_hosts_scoped=True):
    available = sorted(set(available))
    selected = set()
    for path in paths:
        path = path.strip()
        if not path or path.endswith('.md'):
            continue
        if path.startswith('common/torque/') and cpp_hosts_scoped:
            continue
        if path in HOST_TESTS:
            continue
        if path.startswith('scripts/ci/'):
            continue  # tested by the selector unit tests in the changes job
        if path.startswith(('common/', 'scripts/')):
            return available
        folder = path.split('/', 1)[0]
        if folder in available:
            selected.add(folder)
    return sorted(selected)

if __name__ == '__main__':
    repo = Path(__file__).resolve().parents[2]
    available = [p.name for p in repo.glob('graal-*')
                 if (p / 'src').is_dir() and not p.name.startswith('graal-3d-')]
    scoped = (repo / '.github/workflows/cpp-hosts.yml').is_file()
    print(' '.join(select_builds(sys.stdin, available, cpp_hosts_scoped=scoped)))
