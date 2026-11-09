"""Modern host startup regression harness; not an original-client boot test."""
import pathlib
import subprocess
import sys
import tempfile
repo = pathlib.Path(__file__).resolve().parents[2]
for version, demo in [('304', 'camera-move.cs'), ('4208', 'level-tile.cs')]:
    binary = repo / 'common' / 'torque' / ('host' + version) / 'build' / ('host' + version)
    if sys.platform == 'win32':
        binary = binary.with_suffix('.exe')
    source = repo / 'common' / 'torque' / ('host' + version) / 'scripts' / demo
    def run(*args):
        return subprocess.run([str(binary), *args, '--host', '0.0.0.0'],
                              cwd=repo, capture_output=True, text=True, timeout=15)
    with tempfile.TemporaryDirectory(prefix='host script ') as scratch:
        missing = pathlib.Path(scratch) / 'missing script.cs'
        result = run('--script', str(missing))
        assert result.returncode != 0, 'missing explicit script reported success'
        assert str(missing) in result.stderr, result.stderr
        assert 'could not open' in result.stderr, result.stderr
        assert 'login-plain:' not in result.stdout, 'missing script reached login builder'
        assert 'first-frame-bytes:' not in result.stdout, 'missing script produced a frame'
        selected = pathlib.Path(scratch) / 'chosen script.cs'
        selected.write_bytes(source.read_bytes())
        result = run('--script', str(selected))
        assert ('script ' + str(selected)) in result.stdout, result.stdout + result.stderr
        assert 'login-plain:' in result.stdout, 'valid explicit script did not complete'
        assert 'refusing non-loopback' in result.stderr, result.stderr
        # The diagnostic-only rejection above guarantees no socket is opened.
        result = run()
        assert 'login-plain:' in result.stdout, result.stdout + result.stderr
        assert 'refusing non-loopback' in result.stderr, result.stderr
print('both hosts honor explicit paths and preserve implicit demos')
