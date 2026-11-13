"""Loopback listserver and gserver for the tq-play online test.

The listserver speaks the 3.04 list step: a plain zlib frame with id 7
(key, token, list name) and id 1 (account, password), then gen 5 frames
back: id 0 with the server list (one Classic, one Gold server) and id 2
status. The gserver only records what the client sends in its first frame.
Writes what it saw to the JSON file given, then exits.

With a third argument "fallback", a silent listserver on 127.0.0.2 (same
port) takes the connection and never answers; listserver.txt names it,
and the client must move on to the license.graal host, 127.0.0.1.
"""
import json, socket, struct, sys, threading, zlib

def gchar(n): return bytes([n + 32])
def gstr(s): return gchar(len(s)) + s

class Codec:
    LIM = {2: 0x0C, 4: 0x04, 6: 0x04}
    def __init__(s, key): s.key, s.it = key, 0x4A80B38
    def apply(s, buf, ctype):
        limit = s.LIM.get(ctype, -1)
        out = bytearray(buf)
        for i in range(len(out)):
            if i % 4 == 0:
                if limit == 0: break
                s.it = (s.it * 0x8088405 + s.key) & 0xFFFFFFFF
                if limit > 0: limit -= 1
            out[i] ^= struct.pack('<I', s.it)[i % 4]
        return bytes(out)

def read_frame(conn):
    head = b''
    while len(head) < 2:
        d = conn.recv(2 - len(head))
        if not d: return None
        head += d
    n = struct.unpack('>H', head)[0]
    body = b''
    while len(body) < n:
        d = conn.recv(n - len(body))
        if not d: return None
        body += d
    return body

out_path, ready_path = sys.argv[1], sys.argv[2]
seen = {}
ls, gs = socket.socket(), socket.socket()
for s in (ls, gs):
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    # 60 s: the fallback run presses Connect 10.5 s into tq-play, and a
    # macOS runner can take several seconds more to start it.
    s.bind(('127.0.0.1', 0)); s.listen(4); s.settimeout(60)
lport, gport = ls.getsockname()[1], gs.getsockname()[1]

def listserver():
    conn, _ = ls.accept(); conn.settimeout(10)
    raw = zlib.decompress(read_frame(conn))
    lines = [l for l in raw.split(b'\n') if l]
    key = lines[0][1] - 32
    seen['list_token'] = lines[0][2:].decode('latin1')
    al = lines[1][1] - 32
    seen['list_account'] = lines[1][2:2 + al].decode('latin1')
    servers = [(b'Lab Classic', b'127.0.0.1', str(gport).encode()), (b'P Lab Gold', b'127.0.0.1', b'1')]
    entries = gchar(len(servers)) + b''.join(
        gchar(8) + gstr(n) + gstr(b'English') + gstr(b'desc') + gstr(b'http://lab.invalid/') +
        gstr(b'3.04') + gstr(b'1') + gstr(h) + gstr(p) for n, h, p in servers)
    data = gchar(0) + entries + b'\n' + gchar(2) + b'Lab list\n'
    z = zlib.compress(data)
    body = bytes([4]) + Codec(key).apply(z, 4)
    conn.sendall(struct.pack('>H', len(body)) + body)
    conn.close()

def gserver():
    conn, _ = gs.accept(); conn.settimeout(10)
    body = read_frame(conn) or b''
    try: raw = zlib.decompress(body)
    except Exception: raw = body
    seen['game_first_frame'] = raw.decode('latin1')
    conn.close()

fallback = len(sys.argv) > 3 and sys.argv[3] == 'fallback'
held = []
if fallback:
    silent = socket.socket()
    silent.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    silent.bind(('127.0.0.2', lport)); silent.listen(4); silent.settimeout(60)
    def hold():
        try:
            conn, _ = silent.accept()
            held.append(conn)
            seen['silent_host_asked'] = True
        except OSError: pass
    threading.Thread(target=hold, daemon=True).start()
open(ready_path, 'w').write('%s\n%d\n' % ('127.0.0.2' if fallback else '127.0.0.1', lport))
t1 = threading.Thread(target=listserver); t2 = threading.Thread(target=gserver)
t1.start(); t2.start(); t1.join(); t2.join()
json.dump(seen, open(out_path, 'w'))
