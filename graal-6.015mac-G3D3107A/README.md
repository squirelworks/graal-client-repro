# Graal 6.015 Mac (`G3D3107A`)

The Mac OS X 6.015 client, rebuilt for Linux and Windows. The original is
`Graal.app/Contents/MacOS/Graal` (CFBundleVersion 6.015, 12,643,872 bytes,
SHA-256 `b839b37b47b36eb097892910ab030a4bd764a4653c4763820ed77fecd7af2389`), one program from the `quattro_lib` engine. This folder
starts as a copy of the Windows 6.0.1.5 rebuild (`graal-6.0.1.5-G3D3007A`), the nearest build of
the same engine, and changes the token and the Mac login. This is the 0.0.1
reproduction: hit or miss.

**Evidence: real binary, token read from it.** `G3D3107A` was read from the
connect routine of the x86_64 slice (graal_analysis
`client-internals/version-token-catalogue.md`, grade B): one day after the Windows 6.0.1.5's `G3D3007A`. The
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
| Everything carried over | `../graal-6.0.1.5-G3D3007A/README.md` |

## What differs from the sibling rebuild

| | `graal-6.0.1.5-G3D3007A` | 6.015 Mac (this folder) |
|---|---|---|
| Game token | its own | `G3D3107A` (read from the binary) |
| Login comma list | its platform and four fields | `mac`, two hashes, an empty field, the quoted Darwin kernel string (inferred: the Mac 5.12's shape) |
| OSTYPE, code page | its own | `mac`, 0 (inferred: the Mac 4.04r2 and 5.12 runs) |

The machine hashes are fixed made-up values of the Mac shape: the MD5 hex
of "SquirrelBook en0 MAC AC:04:2D:5E:ED:03" and of "SquirrelFS /etc stat
424243". The kernel string is a made-up SquirrelOS one in the layout of a
Darwin 11 (late 2011) x86_64 string. Nothing is read from the player's machine.

## Units

As in `graal-6.0.1.5-G3D3007A`, with the suffix `6015mac`: `Protocol6015mac`, `GraalClient`,
`Adventure`, `Graal6015mac.dpr`, `ListServer6015mac`, `StartScreen6015mac`, `RunMode`.

## Running it

Put `Graal6015mac` in the root of a 6.015 Mac install (the files inside
`Graal.app`, copied to a Linux or Windows folder) and start it with no
arguments for the start screen.

```
GRAAL_PW=... Graal6015mac --server HOST:PORT --account NAME
GRAAL_PW=... Graal6015mac --server HOST:PORT --account NAME --server-name Classic
Graal6015mac --level some.nw                                          # offline
```

## Not yet, or not known

- [ ] A lab run of the real Mac 6.015 (the x86_64 build needs an Intel macOS VM, 10.6 or later): see `G3D3107A` on the wire and read the login line, OSTYPE and code page.
- [ ] Everything past the token: the ids handled, the Login mode and the framing are the sibling's.
- [ ] A macOS build of this rebuild.
- [ ] No side-by-side run against the real client; that is 0.0.2 work.
