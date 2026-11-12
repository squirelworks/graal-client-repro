#!/usr/bin/env python3
"""Per-program Torque module profiles: manifests as build inputs (#152).

Each manifests/<program>.list names the module directories one program
links, one per line, relative to common/torque/. This script makes that
list the actual input of a Free Pascal build:

  profiles.py check
      Every manifest names only existing module directories, each once,
      and lists exactly the modules CUTS.md marks "yes" for that program.
      A module CUTS.md marks no, names or a dash is rejected.

  profiles.py build <program> <outdir> [--fpc FPC]
      Writes <outdir>/<Program>.dpr, a program that uses the stub unit of
      every listed module and nothing else, and compiles it with only the
      listed module directories on the unit path (-Fu). A unit the
      manifest does not list cannot be found, so the build proves which
      modules the profile selects.

  profiles.py fpc-args <program>
      Prints the -Fu arguments for that program's modules, one per line.

The stub units are a scaffold (no types, no state). This checks module
selection, not any engine behaviour. Modern build tooling, not historical
client code.
"""
import argparse
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TORQUE = os.path.dirname(HERE)
CUTS = os.path.join(TORQUE, "CUTS.md")

# Manifest name -> the CUTS.md column header for that program.
COLUMNS = {
    "3.04": "3.04",
    "4.04r2-g3d": "4.04r2 3D",
    "4.2.0.8-launcher": "4.2.0.8 launcher",
    "4.2.0.8-engine": "4.2.0.8 engine",
    "4.2.0.8-g3d": "4.2.0.8 3D",
    "5.0.0.7-launcher": "5.0.0.7 launcher",
    "5.0.0.7-engine": "5.0.0.7 engine",
    "5.0.0.7-g3d": "5.0.0.7 3D",
    "5.30": "5.30 / 5.31",
    "6.x": "6.x",
}


class ProfileError(Exception):
    pass


def read_manifest(path):
    """Module names in file order. Blank lines and # comments are skipped."""
    mods = []
    with open(path, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            s = line.split("#", 1)[0].strip()
            if not s:
                continue
            if not re.fullmatch(r"[a-z0-9][a-z0-9-]*", s):
                raise ProfileError("%s:%d: %r is not a module directory name" % (path, n, s))
            if s in mods:
                raise ProfileError("%s:%d: %s listed twice" % (path, n, s))
            mods.append(s)
    return mods


def read_cuts(path=CUTS):
    """{column header: {module: cell}} from the CUTS.md module table."""
    header = None
    table = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            if not line.startswith("|"):
                if header is not None and table:
                    break
                continue
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if header is None:
                if cells and cells[0] == "Module":
                    header = cells
                continue
            if set("".join(cells)) <= set("-: "):
                continue
            mod = cells[0].strip("`")
            for col, cell in zip(header[2:], cells[2:]):
                table.setdefault(col, {})[mod] = cell
    if header is None:
        raise ProfileError("%s: no module table" % path)
    return table


def module_unit(mod):
    """The one Tq*.pas stub unit name in a module directory."""
    d = os.path.join(TORQUE, mod)
    if not os.path.isdir(d):
        raise ProfileError("%s: no module directory common/torque/%s" % (mod, mod))
    units = sorted(f[:-4] for f in os.listdir(d) if f.startswith("Tq") and f.endswith(".pas"))
    if len(units) != 1:
        raise ProfileError("%s: expected one Tq*.pas unit, found %s" % (mod, units or "none"))
    return units[0]


def check_profile(name, mods, table):
    col = COLUMNS.get(name)
    if col is None:
        raise ProfileError("%s: no CUTS.md column is mapped to this manifest" % name)
    if col not in table:
        raise ProfileError("%s: CUTS.md has no column %r" % (name, col))
    cells = table[col]
    for m in mods:
        if m not in cells:
            raise ProfileError("%s: %s is not a CUTS.md module" % (name, m))
        if cells[m] != "yes":
            raise ProfileError("%s: %s is %r in CUTS.md, not linked" % (name, m, cells[m]))
        module_unit(m)
    missing = [m for m, c in cells.items() if c == "yes" and m not in mods]
    if missing:
        raise ProfileError("%s: CUTS.md links %s, the manifest does not" % (name, ", ".join(missing)))


def manifest_path(name):
    return os.path.join(HERE, name + ".list")


def all_names():
    return sorted(f[:-5] for f in os.listdir(HERE) if f.endswith(".list"))


def check_all():
    table = read_cuts()
    names = all_names()
    unmapped = sorted(set(COLUMNS) - set(names))
    if unmapped:
        raise ProfileError("mapped programs with no manifest: %s" % ", ".join(unmapped))
    for name in names:
        check_profile(name, read_manifest(manifest_path(name)), table)
    return names


def program_name(name):
    return "Profile" + re.sub(r"[^A-Za-z0-9]", "_", name)


def write_program(name, mods, outdir):
    prog = program_name(name)
    units = [module_unit(m) for m in mods]
    lines = ["{ Generated by common/torque/manifests/profiles.py from %s.list. }" % name,
             "program %s;" % prog, "", "{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}", ""]
    if units:
        lines += ["uses", "  " + ",\n  ".join(units) + ";", ""]
    lines += ["begin", "end.", ""]
    os.makedirs(outdir, exist_ok=True)
    path = os.path.join(outdir, prog + ".dpr")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    return path


def fpc_args(mods):
    return ["-Fu" + os.path.join(TORQUE, m) for m in mods]


def build(name, mods, outdir, fpc="fpc", extra_units=()):
    """Compile the profile program for name with modules mods. extra_units
    are used by the program without adding their directories: the
    selection check uses that to show an unlisted module cannot link."""
    src = write_program(name, mods, outdir)
    if extra_units:
        with open(src, encoding="utf-8") as f:
            text = f.read()
        more = ",\n  ".join(extra_units)
        if "\nuses\n" in text:
            text = text.replace(";\n\nbegin", ",\n  " + more + ";\n\nbegin", 1)
        else:
            text = text.replace("\nbegin", "\nuses\n  " + more + ";\n\nbegin", 1)
        with open(src, "w", encoding="utf-8") as f:
            f.write(text)
    units = os.path.join(outdir, "units")
    os.makedirs(units, exist_ok=True)
    cmd = [fpc, "-Mdelphi", "-Sh", "-vew", "-FU" + units, "-FE" + outdir] + fpc_args(mods) + [src]
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("check")
    b = sub.add_parser("build")
    b.add_argument("program")
    b.add_argument("outdir")
    b.add_argument("--fpc", default=os.environ.get("FPC", "fpc"))
    a = sub.add_parser("fpc-args")
    a.add_argument("program")
    args = ap.parse_args(argv)
    try:
        if args.cmd == "check":
            for name in check_all():
                mods = read_manifest(manifest_path(name))
                print("ok  %-18s %s" % (name, " ".join(mods) or "(no module)"))
        elif args.cmd == "fpc-args":
            table = read_cuts()
            mods = read_manifest(manifest_path(args.program))
            check_profile(args.program, mods, table)
            print("\n".join(fpc_args(mods)))
        else:
            table = read_cuts()
            mods = read_manifest(manifest_path(args.program))
            check_profile(args.program, mods, table)
            r = build(args.program, mods, args.outdir, args.fpc)
            sys.stdout.write(r.stdout)
            if r.returncode != 0:
                return r.returncode
    except ProfileError as e:
        print("error: %s" % e, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
