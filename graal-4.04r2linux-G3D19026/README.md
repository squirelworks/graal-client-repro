# Graal 4.04r2 Linux (`G3D19026`)

The Linux 4.04r2 client, rebuilt for Linux and Windows. The original is one
x86 program (autopackage `graal4setup.package`, SoftwareVersion 4.0402,
binary SHA-256 `50f2057117cfafd5a1151d6e6fdd1413095fa71445ff274bf923ce7dc04198aa`,
built 2006-03-04) from the 4.x engine. This folder starts as a copy of the
4.11 Mac rebuild (`graal-4.11mac-G3D27076`), the 4.x engine on a Unix
system, and changes the token and the platform. This is the 0.0.1
reproduction: hit or miss.

**Evidence: real binary, token seen on the wire.** The real Linux 4.04r2
logged in to a local lab server, and its first frame carried `G3D19026`
(graal_analysis `protocol/linux-local-login-matrix.md`). Nothing else of
its login line was published, so the rest is inferred.

## Sources

From [graal_analysis](https://github.com/squirelworks/graal_analysis), not
from decompiled code:

| Area | Notes |
|---|---|
| Token | `protocol/linux-local-login-matrix.md` [cap]; `client-internals/version-token-catalogue.md` (W) |
| The binary (hash, package, build date) | Batch-1 `Web-Discovered/METADATA.md` (2026-11-13) |
| Login server, login line, ids handled | `protocol/v4x-clients.md`, `version-profiles/4.04-4.20.toml` |
| The Unix 4.x login line shape | the 4.11 Mac run, `version-profiles/lab-mac-tiger-2026-10-31.md` |
| Everything carried over | `../graal-4.11mac-G3D27076/README.md` |

## What differs from the 4.11 Mac rebuild

| | 4.11 Mac | 4.04r2 Linux (this folder) |
|---|---|---|
| Game token | `G3D27076` | `G3D19026` (seen on the wire) |
| Login comma list | `mac`, two hashes, empty | `linux`, two hashes, empty (inferred: the Linux 6.x name, the Mac 4.x shape) |
| OSTYPE, code page | `mac`, 0 | `linux`, 1250 (the Linux 3.04's lab values, assumed) |

The machine hashes are fixed made-up values of the original's shape: the
MD5 hex of "SquirrelNIC eth0 MAC AC:04:2D:5E:ED:02" and of "SquirrelFS
/etc inode 424242". Nothing is read from the player's machine.

The empty 44, the 99 server ids, the Login session and the messages after
login are the 4.11 Mac's.

## Units

As in the 4.11 Mac, with the suffix `404r2lx`: `Protocol404r2lx`,
`GraalClient`, `Adventure`, `Graal404r2lx.dpr`, `ListServer404r2lx`,
`StartScreen404r2lx`, `RunMode`.

## Running it

Put `Graal404r2lx` in the root of a 4.04r2 Linux install and start it with
no arguments for the start screen. It finds the install's files from there,
or from `graal-assets/4.04r2linux/`, `4.04r2/`, `4.20r8/`, then `common/`,
next to it.

```
GRAAL_PW=... Graal404r2lx --server HOST:PORT --account NAME
GRAAL_PW=... Graal404r2lx --server HOST:14900 --account NAME --server-name Login
Graal404r2lx --level some.nw                  # offline
```

## Not yet, or not known

- [ ] The rest of the real login line (platform name and machine fields), OSTYPE and the code page: read them from a Linux lab VM capture.
- [ ] The ids handled, the empty 44 and the messages after login: taken from the 4.11 Mac.
- [ ] Whether the Linux build compresses every frame and how it steps the cipher (the Mac 4.x rule is used).
- [ ] The install's files compared with the Windows 4.04r2's.
- [ ] The 3D mode.
- [ ] No side-by-side run against the real Linux 4.04r2; that is 0.0.2 work.
