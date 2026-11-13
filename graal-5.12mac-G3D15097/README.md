# Graal 5.12 Mac (`G3D15097`)

The Mac OS X 5.12 client, rebuilt for Linux and Windows. The original is
one PowerPC program built from the same engine source as the Windows 5.12.
This folder starts as a copy of the Windows 5.12 rebuild
(`graal-5.12-G3D14097`) and changes what the Mac lab run showed. This is
the 0.0.1 reproduction: hit or miss.

**Evidence: real binary, token seen on the wire.** The real Mac 5.12 ran
unchanged on Mac OS X 10.4 in an emulated PowerPC machine (qemu) against a
lab server, logged in, took the 178 warp, loaded the level and walked
(graal_analysis `version-profiles/lab-mac-ppc-404r2-512-2026-11-13.md`).

## Sources

From [graal_analysis](https://github.com/squirelworks/graal_analysis), not
from decompiled code:

| Area | Notes |
|---|---|
| Token, login comma list, OSTYPE and code page, cipher step, compression | `version-profiles/lab-mac-ppc-404r2-512-2026-11-13.md` [cap] |
| Token grade | `client-internals/version-token-catalogue.md` (W) |
| Everything carried over | `../graal-5.12-G3D14097/README.md` |

## What differs from the Windows 5.12 rebuild

| | 5.12 Windows | 5.12 Mac (this folder) |
|---|---|---|
| Game token | `G3D14097` | `G3D15097` (seen on the wire) |
| Login comma list | `win`, three hashes, the quoted Windows version | `mac`, two hashes, an empty field, then the quoted Darwin kernel string as the fifth field (the lab run captured the two hashes and the fifth field; the empty fourth is the Mac 4.11's) |
| OSTYPE, code page | `win`, 1250 | `mac`, 0 (seen in the run) |
| Cipher step | packed bodies rounded down | the same (seen in the run) |
| Compression | every frame, short ones too | not every frame (seen in the run); the 4.04r2 rule is used: zlib only where it is shorter |
| Program icon | the Windows launcher's | none taken (the Mac program has an `.icns`, not read) |

The machine hashes are fixed made-up values of the original's shape: the
MD5 hex of "SquirrelBook en0 MAC AC:04:2D:5E:ED:03" and of "SquirrelFS
/etc stat 424243". The kernel string is a made-up SquirrelOS one in the
layout of a Mac OS X 10.4 (Darwin 8) string. Nothing is read from the
player's machine.

## Units

As in the Windows 5.12, with the suffix `512mac`: `Protocol512mac`,
`GraalClient`, `Adventure`, `Graal512mac.dpr`, `ListServer512mac`,
`StartScreen512mac`, `PlayerList512mac`, `Tray512mac`, `RunMode`.

## Running it

Put `Graal512mac` in the root of a 5.12 Mac install (the files inside
`Graal.app`, copied to a Linux or Windows folder) and start it with no
arguments for the start screen.

```
GRAAL_PW=... Graal512mac --server HOST:PORT --account NAME
Graal512mac --level some.nw                  # offline
```

## Not yet, or not known

- [ ] The Mac server-to-client switch for 5.12 (its profile row borrows the Windows set); the ids handled are the Windows 5.12's.
- [ ] The Mac rule for which short bodies are compressed (the 4.04r2 one is used).
- [ ] The Windows launcher's Players window and tray icon are carried over; the Mac program is not a Delphi launcher and may have neither.
- [ ] A rerun of the real Mac 5.12 against a server that knows the Mac tokens (the lab world drew black because the bundle has no `pics1.png` and the server refused it).
- [ ] A macOS build of this rebuild.
- [ ] No side-by-side run against the real Mac 5.12; that is 0.0.2 work.
