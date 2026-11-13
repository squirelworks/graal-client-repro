#!/usr/bin/env python3
"""Checks that the built engine library exports one graal_set<Name> per
slot in include/graalengine_slots.def, plus the entry points, and nothing
else under those prefixes."""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEF = os.path.join(HERE, "..", "include", "graalengine_slots.def")
ENTRY = [
    "graal_engineInitialize", "loadGraalGui", "renderGraalCanvas", "renderGraal",
    "invokeGraalKeyboardEvent", "invokeGraalMouseEvent", "startOfflineMode",
    "connectToGraalServer", "openGraalServerList", "enableScriptedControls",
    "prepareGraalShutdown", "shutdownGraalEngine", "graalengine_abi",
    "graalengine_slotCount", "graalengine_slotName", "graalengine_slotBuilds",
    "graalengine_setBuild", "graalengine_build", "graalengine_graal3DLoginStep", "graalengine_logLine",
    "isGraal3DMode", "getGraalLoginInfo", "setGraal3DConnectionError",
]


def slot_names():
    text = open(DEF, encoding="utf-8").read()
    return re.findall(r"^GE_SLOT\((\w+),", text, re.M)


def exported(lib):
    if lib.lower().endswith(".dll"):
        out = subprocess.run(["objdump", "-p", lib], capture_output=True, text=True, check=True).stdout
        names = set()
        in_table = False
        for line in out.splitlines():
            if "[Ordinal/Name Pointer] Table" in line:
                in_table = True
                continue
            if in_table:
                # "[   0] name", or with newer binutils
                # "[   0] +base[   1] 0000 name": the name is the last word.
                m = re.match(r"\s*\[\s*\d+\]\s.*?(\S+)\s*$", line)
                if m:
                    names.add(m.group(1))
                elif line.strip() == "":
                    in_table = False
        return names
    out = subprocess.run(["nm", "-D", "--defined-only", lib], capture_output=True, text=True, check=True).stdout
    return {l.split()[-1] for l in out.splitlines() if l.strip()}


def resolvable(lib, want):
    """The names a loaded library resolves (ctypes, so no objdump format)."""
    import ctypes
    handle = ctypes.CDLL(os.path.abspath(lib))
    return {n for n in want if hasattr(handle, n)}


def main():
    lib = sys.argv[1]
    want = {"graal_set" + n for n in slot_names()} | set(ENTRY)
    have = exported(lib)
    if lib.lower().endswith(".dll") and not (want & have):
        # objdump's export listing differs between binutils builds; fall
        # back to asking the loader.
        have = resolvable(lib, want)
    missing = sorted(want - have)
    extra = sorted(n for n in have - want if n.startswith(("graal_", "graalengine_")))
    for n in missing:
        print("missing export:", n)
    for n in extra:
        print("unexpected export:", n)
    if missing or extra:
        return 1
    print("exports: %d setters and %d entry points" % (len(slot_names()), len(ENTRY)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
