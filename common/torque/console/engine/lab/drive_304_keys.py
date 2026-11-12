#!/usr/bin/env python3
"""Play a key script (keys-304.txt format) into the original 3.04 client.

    python3 -I drive_304_keys.py --exe PATH/TO/graal --keys keys-304.txt \
        --prefs PREFS_DIR --out OUT_DIR [--display :99] [--start-wait 15]

Runs in the lab VM, never in CI. Starts the client (under Xvfb when
--display names a server this script starts), waits for its window, sends
each event with xdotool, waits for the client to quit, then copies
console.log and graaldata/client/config.cs from PREFS_DIR into OUT_DIR for
compare_304_input.py. Needs xdotool (and Xvfb for --display).
"""
import argparse
import os
import shutil
import subprocess
import sys
import time

KEYSYMS = {
    "enter": "Return", "escape": "Escape", "up": "Up", "down": "Down",
    "left": "Left", "right": "Right", "space": "space", "backspace": "BackSpace",
    "delete": "Delete", "home": "Home", "end": "End", "tab": "Tab",
}


def keysym(name, mods):
    k = KEYSYMS.get(name.lower())
    if k is None:
        k = name.upper() if name.lower().startswith("f") and name[1:].isdigit() else name
    return "+".join([m for m in mods] + [k])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--exe", required=True)
    ap.add_argument("--keys", required=True)
    ap.add_argument("--prefs", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--display")
    ap.add_argument("--start-wait", type=float, default=15.0)
    ap.add_argument("--step", type=float, default=0.3)
    a = ap.parse_args()

    env = dict(os.environ)
    xvfb = None
    if a.display:
        xvfb = subprocess.Popen(["Xvfb", a.display, "-screen", "0", "1024x768x24"])
        env["DISPLAY"] = a.display
        time.sleep(2)
    exe = os.path.abspath(a.exe)
    game = subprocess.Popen([exe], cwd=os.path.dirname(exe), env=env)
    time.sleep(a.start_wait)
    # The 3.04 window sets no _NET_WM_PID, so a --sync search by pid never
    # returns; search once by pid, then by the window title.
    win = subprocess.run(["xdotool", "search", "--pid", str(game.pid)], env=env,
                         capture_output=True, text=True).stdout.split()
    if not win:
        win = subprocess.run(["xdotool", "search", "--name", "^Graal$"], env=env,
                             capture_output=True, text=True).stdout.split()
    if not win:
        print("no window for the client", file=sys.stderr)
        game.kill()
        return 1
    xd = ["xdotool"]
    # Bare Xvfb has no _NET_ACTIVE_WINDOW; the keys still reach the only window.
    subprocess.run(xd + ["windowactivate", win[-1]], env=env, stderr=subprocess.DEVNULL)

    with open(a.keys, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\r\n")
            words = line.split()
            if not words or words[0].startswith("#"):
                continue
            verb = words[0]
            if verb == "type":
                text = line[line.index("type") + 4:]
                text = text[1:] if text.startswith(" ") else text
                subprocess.run(xd + ["type", "--delay", "40", text], env=env)
            elif verb == "advance":
                time.sleep(int(words[1]) / 1000.0)
            elif verb in ("key", "down", "up"):
                cmd = {"key": "key", "down": "keydown", "up": "keyup"}[verb]
                subprocess.run(xd + [cmd, keysym(words[1], words[2:])], env=env)
            else:
                print("bad line: " + line, file=sys.stderr)
                return 1
            time.sleep(a.step)

    try:
        game.wait(timeout=30)
    except subprocess.TimeoutExpired:
        game.kill()
        print("client did not quit; files may be incomplete", file=sys.stderr)
    if xvfb:
        xvfb.terminate()
    os.makedirs(os.path.join(a.out, "graaldata", "client"), exist_ok=True)
    for rel in ("console.log", os.path.join("graaldata", "client", "config.cs")):
        src = os.path.join(a.prefs, rel)
        if os.path.exists(src):
            shutil.copyfile(src, os.path.join(a.out, rel))
        else:
            print("missing " + src, file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
