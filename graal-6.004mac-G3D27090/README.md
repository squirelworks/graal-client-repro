# Graal 6.004 Mac (`G3D27090`)

The Mac OS X 6.004 client, rebuilt for Linux and Windows. The original is
`Graal.app/Contents/MacOS/Graal` (CFBundleVersion 6.004, 13,806,456 bytes,
SHA-256 `14b3dd96520271712fb9d1b573eba5ff9bea4431a4ec140981ce5c3728697492`), one program from the `quattro_lib` engine. This folder
starts as a copy of the Linux 6.x beta of 27 June 2011 rebuild (`graal-6.00beta-20110627-G3D28090`), the nearest build of
the same engine, and changes the token and the Mac login. This is the 0.0.1
reproduction: hit or miss.

**Evidence: real binary, token read from it.** `G3D27090` was read from the
connect routine of the x86_64 slice (graal_analysis
`client-internals/version-token-catalogue.md`, grade B): the Mac download of the June 2011 beta, one day before the Linux beta's `G3D28090`. The
binary has not been run in a lab, so everything past the token is
inferred.

## Sources

From [graal_analysis](https://github.com/squirelworks/graal_analysis), not
from decompiled code:

| Area | Notes |
|---|---|
| Token | `client-internals/version-token-catalogue.md` (B, 2026-11-13) |
| The binary (hash, bundle version) | Batch-1 `Web-Discovered/METADATA.md` and `TOKENS.md` (2026-11-13) |
| The Mac login line, OSTYPE and code page (taken from 5.12 Mac) | `version-profiles/lab-mac-ppc-404r2-512-2026-11-13.md` |
| Login line, framing, ids both ways | `protocol/v6x-clients.md` |
| Everything carried over | `../graal-6.00beta-20110627-G3D28090/README.md` |

## What differs from the sibling rebuild

| | `graal-6.00beta-20110627-G3D28090` | 6.004 Mac (this folder) |
|---|---|---|
| Game token | its own | `G3D27090` (read from the binary) |
| Login comma list | its platform and four fields | `mac`, two hashes, an empty field, the quoted Darwin kernel string (inferred: the Mac 5.12's shape) |
| OSTYPE, code page | its own | `mac`, 0 (inferred: the Mac 4.04r2 and 5.12 runs) |

The machine hashes are fixed made-up values of the Mac shape: the MD5 hex
of "SquirrelBook en0 MAC AC:04:2D:5E:ED:03" and of "SquirrelFS /etc stat
424243". The kernel string is a made-up SquirrelOS one in the layout of a
Darwin 10 (2011) x86_64 string. Nothing is read from the player's machine.

## Units

As in `graal-6.00beta-20110627-G3D28090`, with the suffix `6004mac`: `Protocol6004mac`, `GraalClient`,
`Adventure`, `Graal6004mac.dpr`, `ListServer6004mac`, `StartScreen6004mac`, `RunMode`.

## Running it

Put `Graal6004mac` in the root of a 6.004 Mac install (the files inside
`Graal.app`, copied to a Linux or Windows folder) and start it with no
arguments for the start screen.

```
GRAAL_PW=... Graal6004mac --server HOST:PORT --account NAME
GRAAL_PW=... Graal6004mac --server HOST:PORT --account NAME --server-name Classic
Graal6004mac --level some.nw                                          # offline
```

## Not yet, or not known

- [ ] A lab run of the real Mac 6.004 (the x86_64 build needs an Intel macOS VM, 10.6 or later): see `G3D27090` on the wire and read the login line, OSTYPE and code page.
- [ ] Everything past the token: the ids handled, the Login mode and the framing are the sibling's.
- [ ] A macOS build of this rebuild.
- [ ] No side-by-side run against the real client; that is 0.0.2 work.
