#!/usr/bin/env python3
"""Checks that the built 3D library exports its entry points and nothing
else under the graal3dengine_ and Graal3D prefixes."""
import os
import re
import subprocess
import sys

WANT = {
    "loadGraal3DEngine", "runGraal3DEngine", "endGraal3DEngine", "resizeGraal3DWindow",
    "toggleGraal3DFullScreen", "graal3dengine_abi", "graal3dengine_loginStep", "graal3dengine_state",
    "graal3dengine_ghostCount", "graal3dengine_setConnectSequence",
}


def exported(lib):
    if lib.lower().endswith(".dll"):
        import ctypes
        handle = ctypes.CDLL(os.path.abspath(lib))
        return {n for n in WANT if hasattr(handle, n)}
    if sys.platform == "darwin":
        # Mach-O: the external defined symbols, with C's leading underscore.
        out = subprocess.run(["nm", "-gU", lib], capture_output=True, text=True, check=True).stdout
        return {l.split()[-1].removeprefix("_") for l in out.splitlines() if l.strip()}
    out = subprocess.run(["nm", "-D", "--defined-only", lib], capture_output=True, text=True, check=True).stdout
    return {l.split()[-1] for l in out.splitlines() if l.strip()}


def main():
    lib = sys.argv[1]
    have = exported(lib)
    missing = sorted(WANT - have)
    extra = sorted(n for n in have - WANT if re.search(r"graal3dengine_|Graal3D", n))
    for n in missing:
        print("missing export:", n)
    for n in extra:
        print("unexpected export:", n)
    if missing or extra:
        return 1
    print("exports: %d entry points" % len(WANT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
