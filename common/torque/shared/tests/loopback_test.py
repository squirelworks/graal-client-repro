"""Modern loopback harness; first-frame delivery is not historical login."""
import pathlib
import socket
import subprocess
import sys
import threading
import zlib
host = str(pathlib.Path(sys.argv[1]).resolve())
repo = pathlib.Path(__file__).resolve().parents[4]
expected = (b'%!G3D03014#lab#lab\nEEnglish\nB     bigmap.txt\nB     minimap.txt\n'
            if sys.argv[2] == '304' else b'%!G3D20126#lab#labwin,c2482de76c59ac3c4ce0b7e065a2d09c,3c639304427ab3b3c6439a39c31c9df5,217767adb74e936b5ee209ed65ecc400\n')
for destination in ('127.0.0.1', 'localhost'):
    received, failures = [], []
    with socket.socket() as listener:
        listener.bind(('127.0.0.1', 0))
        listener.listen(1)
        listener.settimeout(10)
        port = listener.getsockname()[1]
        def receive():
            try:
                with listener.accept()[0] as peer:
                    peer.settimeout(5)
                    data = bytearray()
                    while True:
                        chunk = peer.recv(4096)
                        if not chunk:
                            break
                        data.extend(chunk)
                    received.append(bytes(data))
            except Exception as exc:
                failures.append(str(exc))
        worker = threading.Thread(target=receive)
        worker.start()
        result = subprocess.run([host, '--host', destination, '--port', str(port)],
                                capture_output=True, text=True, timeout=15, cwd=repo)
        worker.join(11)
        assert not worker.is_alive(), 'receiver did not finish'
        assert not failures, failures
        assert result.returncode == 0, result.stdout + result.stderr
        assert 'sent ' in result.stdout, result.stdout
        assert len(received) == 1, 'no delivered frame'
        wire = received[0]
        assert int.from_bytes(wire[:2], 'big') == len(wire) - 2
        assert zlib.decompress(wire[2:]) == expected, 'wrong profile delivered'
# Unspecified local address tests refusal without contacting a real service.
result = subprocess.run([host, '--host', '0.0.0.0'], capture_output=True,
                        text=True, timeout=15, cwd=repo)
assert result.returncode != 0, 'non-loopback destination accepted'
assert 'refusing non-loopback' in result.stderr, result.stderr
print('loopback first-frame delivery and destination refusal passed')
