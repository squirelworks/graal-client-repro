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

tq-boot starts with no prefs. The stage 0 run was the original's second
start, so it first ran the prefs.cs its first start exported; that sets the
same values with the same types, so the exports compare line for line.
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
    # Engine output while the video device starts (createCanvas): GUI/video stage.
    "console": "lines from 'Activating the OpenGL display device...' to the next blank line",
    # mainMenuGui::onWake runs when the canvas wakes its content; the GUI
    # stage then execs the language file twice (onWake and the language
    # menu's onSelect).
    "open-order": ["graaldata/languages/languageEnglish.cs.dso"] * 2,
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
        subprocess.run([args.tq_boot, "--root", args.install, "--prefs", prefs, "--log", log,
                        "--trace", trace, "--exit"], check=True, stdout=subprocess.DEVNULL)
        ok = True
        ok &= report("console.log", console_lines(read(os.path.join(args.capture, "console.log"))),
                     console_lines(read(log)))
        real_dso = [l.split(" ")[0] for l in read(os.path.join(args.capture, "open-order.txt")).splitlines()
                    if l.endswith(".dso O_RDONLY") and not l.startswith("~prefs/")]
        ours = [l[5:] + ".dso" for l in read(trace).splitlines()
                if l.startswith("exec ") and ":" not in l]
        missing_ok = list(KNOWN["open-order"])
        filtered_real = []
        for f in real_dso:
            if f in missing_ok and f not in ours[len(filtered_real):]:
                missing_ok.remove(f)
                continue
            filtered_real.append(f)
        print(f"compiled scripts run: {len(ours)}; original opened {len(real_dso)}; "
              f"{len(real_dso) - len(filtered_real)} wait on the GUI stage [known]")
        ok &= report("exec order", filtered_real, ours)
        for rel in ("graaldata/client/prefs.cs", "common/client/prefs.cs"):
            ok &= report(rel, read(os.path.join(args.capture, rel)).split("\r\n"),
                         read(os.path.join(prefs, rel)).split("\r\n"), KNOWN["prefs"])
        rel = "graaldata/client/config.cs"
        ok &= report(rel, read(os.path.join(args.capture, rel)).split("\n"),
                     read(os.path.join(prefs, rel)).split("\n"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
