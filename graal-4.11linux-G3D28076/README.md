# Graal 4.11 Linux (`G3D28076`)

The Linux 4.11 client, rebuilt for Linux and Windows. The Linux 4.10r2
sends the same token, so this folder stands for both. The originals are
x86 programs from the 4.x engine (autopackages `graal4setup.package`,
SoftwareVersion 4.11, binary SHA-256
`26a755d10fafd38e4b906094d182f911f7ddbcd37089028b8228421a9ea03e44`, built
2006-09-16; and 4.102, SHA-256
`555778c003cb04863dec62fb9fe31166113f06cde955f8d54ec389e414c5f584`, built
2006-08-19). This folder starts as a copy of the 4.11 Mac rebuild
(`graal-4.11mac-G3D27076`), the same version on another Unix system, and
changes the token and the platform. This is the 0.0.1 reproduction: hit or
miss.

**Evidence: real binary, token read from it.** `G3D28076` was read from
the connect routine of both Linux binaries (graal_analysis
`client-internals/version-token-catalogue.md`, grade B). It is not the
public list's 4.11 token (`G3D26076`, the Windows build's). No lab run yet.

## Sources

From [graal_analysis](https://github.com/squirelworks/graal_analysis), not
from decompiled code:

| Area | Notes |
|---|---|
| Token | `client-internals/version-token-catalogue.md` (B, connect-routine read of both, 2026-11-13) |
| The binaries (hashes, packages, build dates) | Batch-1 `Web-Discovered/METADATA.md` and `TOKENS.md` (2026-11-13) |
| Login server, login line, ids handled | `protocol/v4x-clients.md`, `version-profiles/4.04-4.20.toml` |
| The Unix 4.x login line shape | the 4.11 Mac run, `version-profiles/lab-mac-tiger-2026-10-31.md` |
| Everything carried over | `../graal-4.11mac-G3D27076/README.md` |

## What differs from the 4.11 Mac rebuild

| | 4.11 Mac | 4.11 Linux (this folder) |
|---|---|---|
| Game token | `G3D27076` | `G3D28076` (read from the binary) |
| Login comma list | `mac`, two hashes, empty | `linux`, two hashes, empty (inferred: the Linux 6.x name, the Mac 4.x shape) |
| OSTYPE, code page | `mac`, 0 | `linux`, 1250 (the Linux 3.04's lab values, assumed) |

The machine hashes are fixed made-up values of the original's shape: the
MD5 hex of "SquirrelNIC eth0 MAC AC:04:2D:5E:ED:02" and of "SquirrelFS
/etc inode 424242". Nothing is read from the player's machine.

## Units

As in the 4.11 Mac, with the suffix `411lx`: `Protocol411lx`,
`GraalClient`, `Adventure`, `Graal411lx.dpr`, `ListServer411lx`,
`StartScreen411lx`, `RunMode`.

## Running it

Put `Graal411lx` in the root of a 4.11 (or 4.10r2) Linux install and start
it with no arguments for the start screen. It finds the install's files
from there, or from `graal-assets/4.11linux/`, `4.20r8/`, then `common/`,
next to it.

```
GRAAL_PW=... Graal411lx --server HOST:PORT --account NAME
GRAAL_PW=... Graal411lx --server HOST:14900 --account NAME --server-name Login
Graal411lx --level some.nw                  # offline
```

## Not yet, or not known

- [ ] A lab run of the real 4.11 Linux (Linux lab VM): see `G3D28076` on the wire, and the rest of the login line, OSTYPE and the code page.
- [ ] 4.10r2 is not checked separately; it is taken to behave as 4.11.
- [ ] The ids handled, the empty 44 and the messages after login: taken from the 4.11 Mac.
- [ ] The install's files compared with 4.20r8's.
- [ ] The 3D mode.
- [ ] No side-by-side run against the real client; that is 0.0.2 work.
