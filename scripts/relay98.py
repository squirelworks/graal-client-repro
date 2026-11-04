#!/usr/bin/env python3
"""A lab relay for the 1998 builds (gen 1), for loopback tests only.

Written from graal_analysis protocol/relay-1998.md and the 1.1.9 captures in
client-internals/live-trace-early.md, not from any original server. It groups
connections into named games, gives each an id, pairs players that ask for
it and forwards D lines between partners. Text lines end in LF.

  scripts/relay98.py [--port 14802] [--levels local|remote|none] [--log FILE]

--levels: what follows each N line. local = NR then NL (a server with local
levels), remote = NR alone (levels from the web), none = nothing (servers
before 15th Graal). Binds to 127.0.0.1 only.
"""
import argparse
import selectors
import socket
import sys


class Conn:
    def __init__(self, sock, cid):
        self.sock = sock
        self.id = "0000%04d" % (cid % 10000)
        self.game = None
        self.available = False
        self.partners = set()
        self.inbuf = b""


class Relay:
    def __init__(self, levels, log):
        self.sel = selectors.DefaultSelector()
        self.conns = {}
        self.next_id = 1
        self.levels = levels
        self.log = log

    def note(self, msg):
        self.log.write(msg + "\n")
        self.log.flush()

    def send(self, c, line):
        try:
            c.sock.sendall(line.encode("latin-1") + b"\n")
        except OSError:
            pass

    def by_id(self, cid):
        for c in self.conns.values():
            if c.id == cid:
                return c
        return None

    def leave_party(self, c):
        for pid in list(c.partners):
            p = self.by_id(pid)
            if p is not None:
                p.partners.discard(c.id)
                self.send(p, "C" + c.id)
        c.partners.clear()

    def leave_game(self, c):
        self.leave_party(c)
        if c.game is not None and c.available:
            for o in self.conns.values():
                if o is not c and o.game == c.game:
                    self.send(o, "-" + c.id)
        c.available = False

    def line(self, c, raw):
        s = raw.decode("latin-1")
        if not s:
            return
        cmd, rest = s[0], s[1:]
        if cmd == "N":
            game = rest.split("#", 1)[0]
            self.leave_game(c)
            c.game = game
            c.available = True
            self.note("%s joins %s" % (c.id, game))
            if self.levels in ("local", "remote"):
                self.send(c, "NR")
            if self.levels == "local":
                self.send(c, "NL")
            self.send(c, "I" + c.id)
            for o in self.conns.values():
                if o is not c and o.game == game and o.available:
                    self.send(c, "+" + o.id + "def")
                    self.send(o, "+" + c.id + "def")
        elif cmd == "P":
            o = self.by_id(rest[:8])
            if o is None or o is c or o.game != c.game:
                return
            if o.id in c.partners:
                return
            c.partners.add(o.id)
            o.partners.add(c.id)
            self.note("%s pairs with %s in %s" % (c.id, o.id, c.game))
            self.send(c, "P" + o.id)
            self.send(o, "P" + c.id)
        elif cmd == "C":
            self.leave_party(c)
        elif cmd == "-":
            self.leave_game(c)
        elif cmd == "D":
            for pid in c.partners:
                p = self.by_id(pid)
                if p is not None:
                    self.send(p, s)

    def accept(self, ls):
        sock, _ = ls.accept()
        sock.setblocking(False)
        c = Conn(sock, self.next_id)
        self.next_id += 1
        self.conns[sock] = c
        self.sel.register(sock, selectors.EVENT_READ, self.read)
        self.note("%s connected" % c.id)

    def read(self, sock):
        c = self.conns[sock]
        try:
            data = sock.recv(4096)
        except OSError:
            data = b""
        if not data:
            self.note("%s closed" % c.id)
            self.sel.unregister(sock)
            del self.conns[sock]
            self.leave_party(c)
            for o in self.conns.values():
                self.send(o, "-" + c.id)
            sock.close()
            return
        c.inbuf += data
        while b"\n" in c.inbuf:
            raw, c.inbuf = c.inbuf.split(b"\n", 1)
            self.line(c, raw.rstrip(b"\r"))
        if len(c.inbuf) > 1024:
            c.inbuf = b""

    def run(self, port):
        ls = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        ls.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        ls.bind(("127.0.0.1", port))
        ls.listen(64)
        ls.setblocking(False)
        self.sel.register(ls, selectors.EVENT_READ, self.accept)
        self.note("relay on 127.0.0.1:%d, levels %s" % (port, self.levels))
        while True:
            for key, _ in self.sel.select():
                key.data(key.fileobj)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=14802)
    ap.add_argument("--levels", choices=["local", "remote", "none"], default="local")
    ap.add_argument("--log", default="-")
    a = ap.parse_args()
    log = sys.stderr if a.log == "-" else open(a.log, "a")
    try:
        Relay(a.levels, log).run(a.port)
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
