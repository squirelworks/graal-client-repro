#!/usr/bin/env python3
"""Actual-player numeric CLI regression; authored empty NW, no sockets/windows.

Run with the built quattro-play path. Each subprocess is bounded and owned;
subprocess.run kills and waits for its direct child on timeout. The player
does not launch children. This file itself has not been executed by its author.
"""
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: cli_numeric_test.py PATH_TO_QUATTRO_PLAY")
    player_path = Path(sys.argv[1])
    # Native Windows Python does not apply the shell's implicit .exe lookup.
    if os.name == "nt" and player_path.suffix.lower() != ".exe" and not player_path.exists():
        player_path = Path(str(player_path) + ".exe")
    player = str(player_path.resolve(strict=True))
    failures = []
    checks = 0
    env = os.environ.copy()
    password_var = "QUATTRO_CLI_NUMERIC_TEST_UNSET_PASSWORD"
    env.pop(password_var, None)
    env["GRAAL_SECURE_LOGIN"] = "off"
    with tempfile.TemporaryDirectory(prefix="quattro-numeric-") as tmp:
        root = Path(tmp)
        (root / "levels").mkdir()
        # The production NW reader supplies the all-zero board for this header.
        (root / "levels" / "numeric.nw").write_bytes(b"GLEVNW01\n")
        base = ["--build", "6.03r7", "--secure-login", "off", "--assets", str(root), "--headless"]

        def check(label, args, code, *, timeout=2.0, summary=False):
            nonlocal checks
            checks += 1
            try:
                result = subprocess.run([player] + base + args, cwd=root, env=env,
                                        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                        text=True, timeout=timeout, check=False)
            except subprocess.TimeoutExpired:
                failures.append(label + ": owned player timed out (killed and reaped)")
                return
            if result.returncode != code:
                failures.append(f"{label}: exit {result.returncode}, expected {code}")
            if code == 2:
                if not result.stderr.startswith("usage: quattro-play "):
                    failures.append(label + ": missing actual usage diagnostic")
                if result.stdout or "no level " in result.stderr or "is not set" in result.stderr:
                    failures.append(label + ": progressed beyond numeric validation")
            if summary and "level numeric.nw, lobby no\n" not in result.stdout:
                failures.append(label + ": missing actual offline completion summary")

        # One real finite negative-coordinate run proves the production consumer.
        check("authored offline finite control",
              ["--offline", "numeric.nw", "--size", "64x64", "--x", "-2.25",
               "--y", "1.5", "--seconds", "1"], 0, timeout=4, summary=True)
        # On the old code this one real run is unbounded; kill/reap after2s.
        check("negative duration must reject before play",
              ["--offline", "numeric.nw", "--size", "64x64", "--seconds", "-1"], 2)

        # Missing-level sentinel avoids rendering malformed coordinate values on
        # the baseline. Exit 1 is a baseline failure, not a successful rejection.
        missing = ["--offline", "missing-numeric.nw", "--size", "64x64", "--seconds", "1"]
        for option, values in (
            ("--seconds", ["1junk", "junk", "1.5", "2147483648"]),
            ("--x", ["junk", "1junk", "nan", "inf", "1e999", "1,5"]),
            ("--y", ["nan", "-inf", "2junk"]),
            ("--size", ["64x64junk", "64x", "x64", "63x64", "64x4097", "999999999999999999999x64"]),
        ):
            for value in values:
                check(option + "=" + value, missing + [option, value], 2)
        for option in ("--seconds", "--x", "--y", "--size"):
            check(option + " missing value", missing + [option], 2)

        # The password variable is ABSENT: parsing must reject malformed ports
        # before checking it. Thus even the baseline cannot start a socket.
        for port in ("14900junk", "junk", "0", "65536", "2147483648", ""):
            check("invalid port=" + port,
                  ["--connect", "localhost:" + port, "--account", "authored",
                   "--password-env", password_var, "--seconds", "1"], 2)
        # Valid port reaches the existing missing-password error, proving this
        # control never attempts connection and the negative oracle is distinct.
        checks += 1
        result = subprocess.run([player] + base + ["--connect", "localhost:14900",
                                "--account", "authored", "--password-env", password_var],
                                cwd=root, env=env, capture_output=True, text=True,
                                timeout=2.0, check=False)
        if result.returncode != 2 or result.stderr != password_var + " is not set\n":
            failures.append("valid port must reach existing missing-password diagnostic")
    for failure in failures:
        print("FAIL " + failure)
    print(f"quattro numeric CLI: {checks} checks, {len(failures)} failures")
    return bool(failures)


if __name__ == "__main__":
    raise SystemExit(main())
