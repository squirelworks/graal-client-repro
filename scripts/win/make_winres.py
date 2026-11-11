#!/usr/bin/env python3
"""Give every Pascal client its Windows resources.

For each graal-*/src/<Program>.dpr this makes src/<Program>.rc (the shared
manifest in common/win and a VERSIONINFO block) when it is missing, and
adds the Windows-only {$R <Program>.rc}{$SETPEOPTFLAGS $0140} line after
the program's {$APPTYPE ...} line when it is missing. Run it after adding
a new build folder; it changes nothing that is already in place.

    python3 scripts/win/make_winres.py          make what is missing
    python3 scripts/win/make_winres.py --check  only report, exit 1 if any

See README.md, "Windows says 'Windows protected your PC'".
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
APPTYPE = "{$IFDEF MSWINDOWS}{$IFDEF FPC}{$APPTYPE GUI}{$ELSE}{$APPTYPE CONSOLE}{$ENDIF}{$ENDIF}"

RC = """/* Windows resources for {prog}.exe: the shared manifest and a version
   block, so Windows and antivirus see a named, versioned program
   instead of a bare exe. Built only on Windows ({{$R}} in {prog}.dpr).
   The release workflow stamps the version lines from the tag; keep
   0,0,0,0 and "0.0.0-dev" here. */
1 24 "../../common/win/graal-delphi.manifest"

1 VERSIONINFO
FILEVERSION 0,0,0,0
PRODUCTVERSION 0,0,0,0
FILEFLAGSMASK 0x3F
FILEFLAGS 0x0
FILEOS 0x40004
FILETYPE 0x1
FILESUBTYPE 0x0
BEGIN
  BLOCK "StringFileInfo"
  BEGIN
    BLOCK "040904B0"
    BEGIN
      VALUE "CompanyName", "squirelworks"
      VALUE "FileDescription", "{desc}"
      VALUE "FileVersion", "0.0.0-dev"
      VALUE "InternalName", "{prog}"
      VALUE "LegalCopyright", "graal-delphi contributors. Independent fan rebuild, not affiliated with GraalOnline."
      VALUE "OriginalFilename", "{prog}.exe"
      VALUE "ProductName", "graal-delphi"
      VALUE "ProductVersion", "0.0.0-dev"
      VALUE "Comments", "https://github.com/squirelworks/graal-client-repro"
    END
  END
  BLOCK "VarFileInfo"
  BEGIN
    VALUE "Translation", 0x409, 1200
  END
END
"""


def describe(folder):
    """graal-2.05r2-GNW03081 -> 'graal-delphi 2.05 rev 2 client'."""
    ver = folder[len("graal-"):].rsplit("-", 1)[0]
    m = re.fullmatch(r"b(\d+[a-z]?)", ver)
    if m:
        ver = "beta " + m.group(1)
    else:
        ver = re.sub(r"(\d)r(\d+)$", r"\1 rev \2", ver)
    return "graal-delphi %s client" % ver


def main():
    check = "--check" in sys.argv[1:]
    missing = []
    for dpr in sorted(glob.glob(os.path.join(ROOT, "graal-*", "src", "*.dpr"))):
        src = os.path.dirname(dpr)
        folder = os.path.basename(os.path.dirname(src))
        prog = os.path.splitext(os.path.basename(dpr))[0]
        rc = os.path.join(src, prog + ".rc")
        rel = os.path.relpath(dpr, ROOT)
        if not os.path.exists(rc):
            missing.append(os.path.relpath(rc, ROOT))
            if not check:
                with open(rc, "w", newline="\n") as f:
                    f.write(RC.format(prog=prog, desc=describe(folder)))
        with open(dpr, newline="") as f:
            text = f.read()
        directive = "{$R %s.rc}" % prog
        if directive in text:
            continue
        missing.append(rel)
        if check:
            continue
        if text.count(APPTYPE) != 1:
            sys.exit("%s: no single {$APPTYPE} line to put {$R} after" % rel)
        nl = "\r\n" if "\r\n" in text else "\n"
        add = (nl + "{ Windows: version info and manifest (src/%s.rc), and the DEP and ASLR" % prog + nl
               + "  flags ($0100 NX_COMPAT, $0040 DYNAMIC_BASE; the relocations come from -WR" + nl
               + "  in the Windows build flags). }" + nl
               + "{$IFDEF MSWINDOWS}{$IFDEF FPC}%s{$SETPEOPTFLAGS $0140}{$ENDIF}{$ENDIF}" % directive)
        with open(dpr, "w", newline="") as f:
            f.write(text.replace(APPTYPE, APPTYPE + add))
    for m in missing:
        print(("missing: " if check else "made: ") + m)
    if check and missing:
        print("run: python3 scripts/win/make_winres.py")
        sys.exit(1)


if __name__ == "__main__":
    main()
