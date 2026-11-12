#!/usr/bin/env python3
"""Compare tq-boot against a capture of the original 3.04 starting and quitting.

    python3 -I compare_304_boot.py --install RELEASE_DIR --capture STAGE0_DIR \
        [--tq-boot PATH]

RELEASE_DIR is a 3.04 Linux install (the folder holding common/ and
graaldata/). STAGE0_DIR is a capture of the original client started and
quit (the torque-304 stage 0 run in the project's lab files):

    console.log         the log the original wrote (setLogMode 6)
    open-order.txt      "<path> <open flags>" per file it opened, in order
    graaldata/client/prefs.cs, graaldata/client/config.cs,
    common/client/prefs.cs   what it wrote on exit

The stage 0 run was the original's second start, so tq-boot is run twice
on one prefs directory and the second run is compared: it compiles and runs
the prefs.cs and config.cs the first run wrote, as the original did.
Neither directory is part of the repository. The script prints each
comparison and exits 1 when something differs that is not listed in
KNOWN below (each of those waits on a later stage).
"""
import argparse
import difflib
import os
import subprocess
import sys
import tempfile

# Differences that come from stages this engine does not cover yet.
KNOWN = {
    # Engine output while the video device starts (createCanvas): video stage.
    "console": "lines from 'Activating the OpenGL display device...' to the next blank line",
    # Set by the engine during input and video start-up, after the scripts.
    "prefs": ["$pref::Input::MouseEnabled", "$pref::Video::appliedPref"],
}


def read(path, mode="r"):
    with open(path, mode, newline="" if mode == "r" else None) as f:
        return f.read()


def console_lines(text):
    lines = text.replace("\r\n", "\n").split("\n")
    start = next(i for i, l in enumerate(lines) if l == "--------- Loading MODS ---------")
    out, skipping = [], False
    for line in lines[start:]:
        if line == "Activating the OpenGL display device...":
            skipping = True
        if skipping:
            if line.strip() == "":
                skipping = False
            continue
        out.append(line)
    while out and out[-1] == "":
        out.pop()
    return out


def report(name, want, got, allowed=()):
    diff = [d for d in difflib.unified_diff(want, got, "original", "rebuild", lineterm="", n=0)
            if not d.startswith(("---", "+++", "@@"))]
    unexpected = [d for d in diff if not any(a in d for a in allowed)]
    status = "same" if not diff else ("known differences only" if not unexpected else "DIFFERENT")
    print(f"{name}: {status} ({len(want)} lines)")
    for d in diff:
        print("   " + d + ("" if d in unexpected else "   [known]"))
    return not unexpected


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--install", required=True)
    ap.add_argument("--capture", required=True)
    ap.add_argument("--tq-boot", default=os.path.join(os.path.dirname(__file__), "..", "build", "tq-boot"))
    args = ap.parse_args()

    with tempfile.TemporaryDirectory() as tmp:
        prefs = os.path.join(tmp, "prefs")
        log = os.path.join(tmp, "console.log")
        trace = os.path.join(tmp, "trace.txt")
        for _ in range(2):
            subprocess.run([args.tq_boot, "--root", args.install, "--prefs", prefs, "--log", log,
                            "--trace", trace, "--exit"], check=True, stdout=subprocess.DEVNULL)
        ok = True
        ok &= report("console.log", console_lines(read(os.path.join(args.capture, "console.log"))),
                     console_lines(read(log)))
        # Scripts run, in order: a compiled .dso from the install, or a plain
        # script the game wrote (read from ~prefs and compiled).
        real = []
        for line in read(os.path.join(args.capture, "open-order.txt")).splitlines():
            path, flags = line.rsplit(" ", 1)
            if flags != "O_RDONLY":
                continue
            if path.startswith("~prefs/"):
                if path.endswith(".cs"):
                    real.append(path[len("~prefs/"):])
            elif path.endswith(".dso"):
                real.append(path[:-4])
            elif path.endswith(".cs"):
                real.append(path)
        ours = [l[5:] for l in read(trace).splitlines() if l.startswith("exec ") and ":" not in l]
        ok &= report("scripts run, in order", real, ours)
        for rel in ("graaldata/client/prefs.cs", "common/client/prefs.cs"):
            ok &= report(rel, read(os.path.join(args.capture, rel)).split("\r\n"),
                         read(os.path.join(prefs, rel)).split("\r\n"), KNOWN["prefs"])
        rel = "graaldata/client/config.cs"
        ok &= report(rel, read(os.path.join(args.capture, rel)).split("\n"),
                     read(os.path.join(prefs, rel)).split("\n"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
