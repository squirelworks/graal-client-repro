#!/usr/bin/env python3
"""Compare tq-boot --input against the original 3.04 playing the same keys.

    python3 -I compare_304_input.py --install RELEASE_DIR --capture OUT_DIR \
        --keys keys-304.txt [--tq-boot PATH]

OUT_DIR is what drive_304_keys.py collected from the original: console.log
and graaldata/client/config.cs. tq-boot runs twice on one prefs directory
(the original's capture is also a second start) and the second run gets the
keys. Compared: the console lines from the first typed console line ("==>")
to the end, and config.cs byte for byte. Exits 1 on any difference.
Neither directory is part of the repository.
"""
import argparse
import difflib
import os
import subprocess
import sys
import tempfile


def input_lines(text):
    lines = text.replace("\r\n", "\n").split("\n")
    start = next((i for i, l in enumerate(lines) if l.startswith("==>")), len(lines))
    out = lines[start:]
    while out and out[-1] == "":
        out.pop()
    return out


def show(title, want, got):
    if want == got:
        print("same: " + title)
        return True
    print("DIFFERENT: " + title)
    for line in difflib.unified_diff(want, got, "original", "rebuild", lineterm=""):
        print("  " + line)
    return False


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser()
    ap.add_argument("--install", required=True)
    ap.add_argument("--capture", required=True)
    ap.add_argument("--keys", default=os.path.join(here, "keys-304.txt"))
    ap.add_argument("--tq-boot", default=os.path.join(here, "..", "build", "tq-boot"))
    a = ap.parse_args()

    with tempfile.TemporaryDirectory() as prefs:
        log = os.path.join(prefs, "rebuild-console.log")
        base = [a.tq_boot, "--root", a.install, "--prefs", prefs]
        subprocess.run(base + ["--exit"], check=True, capture_output=True)
        subprocess.run(base + ["--log", log, "--trace", os.path.join(prefs, "trace.txt"),
                               "--input", a.keys], check=True, capture_output=True)
        with open(os.path.join(a.capture, "console.log"), encoding="latin-1") as f:
            want = input_lines(f.read())
        with open(log, encoding="latin-1") as f:
            got = input_lines(f.read())
        ok = show("console lines after the first typed line", want, got)
        with open(os.path.join(a.capture, "graaldata", "client", "config.cs"), "rb") as f:
            want_cfg = f.read()
        path = os.path.join(prefs, "graaldata", "client", "config.cs")
        got_cfg = open(path, "rb").read() if os.path.exists(path) else b""
        ok = show("graaldata/client/config.cs",
                  want_cfg.decode("latin-1").split("\n"), got_cfg.decode("latin-1").split("\n")) and ok
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
