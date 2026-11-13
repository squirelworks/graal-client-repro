# Graal 4.04r2 Mac (`G3D18026`)

The Mac OS X 4.04r2 client, rebuilt for Linux and Windows. The original is
one PowerPC program built from the same engine source as the Windows 4.x
clients. It logs in the same way: no listserver, a game server named
`Login` first, and id 178 hands it on to a game server. This folder starts
as a copy of the 4.11 Mac rebuild (`graal-4.11mac-G3D27076`) and changes
what the Mac 4.04r2 lab run showed. This is the 0.0.1 reproduction: hit or
miss.

**Evidence: real binary, token seen on the wire.** The real Mac 4.04r2 ran
unchanged on Mac OS X 10.4 in an emulated PowerPC machine (qemu) against a
lab server, logged in, took the 178 warp, loaded the level and walked
(graal_analysis `version-profiles/lab-mac-ppc-404r2-512-2026-11-13.md`).

## Sources

From [graal_analysis](https://github.com/squirelworks/graal_analysis), not
from decompiled code:

| Area | Notes |
|---|---|
| Token, login comma list, OSTYPE and code page, cipher step | `version-profiles/lab-mac-ppc-404r2-512-2026-11-13.md` [cap] |
| Token grade | `client-internals/version-token-catalogue.md` (W) |
| Login server, login line, ids handled | `protocol/v4x-clients.md`, `version-profiles/4.04-4.20.toml` |
| What the 4.11 Mac sent where the 4.04r2 run is silent | `version-profiles/lab-mac-tiger-2026-10-31.md` |
| Everything carried over | `../graal-4.11mac-G3D27076/README.md` |

## What differs from the 4.11 Mac rebuild

| | 4.11 Mac | 4.04r2 Mac (this folder) |
|---|---|---|
| Game token | `G3D27076` | `G3D18026` (seen on the wire) |
| Login comma list | `mac`, two hashes, empty | the same shape: the lab run captured `mac` and two machine hashes; the empty fourth field is the 4.11 Mac's |
| OSTYPE, code page | `mac`, 0 | `mac`, 0 (seen in the 4.04r2 run) |
| Cipher step | packed bodies rounded down | the same (seen in the 4.04r2 run) |
| Compression | not every frame | the same (seen in the 4.04r2 run) |

The machine hashes are fixed made-up values of the original's shape: the
MD5 hex of "SquirrelBook en0 MAC AC:04:2D:5E:ED:03" and of "SquirrelFS
/etc stat 424243". Nothing is read from the player's machine.

The empty 44, the 99 server ids, the Login session and the messages after
login are the 4.11 Mac's.

## Units

As in the 4.11 Mac, with the suffix `404r2mac`: `Protocol404r2mac`,
`GraalClient`, `Adventure`, `Graal404r2mac.dpr`, `ListServer404r2mac`,
`StartScreen404r2mac`, `RunMode`.

## Running it

Put `Graal404r2mac` in the root of a 4.04r2 Mac install (the files inside
`Graal.app`, `license/`, `levels/` and `sounds/`, copied to a Linux or
Windows folder) and start it with no arguments for the start screen. It
finds the install's files from there, or from `graal-assets/4.04r2mac/`,
`4.11mac/`, `4.20r8/`, then `common/`, next to it.

```
GRAAL_PW=... Graal404r2mac --server HOST:PORT --account NAME
GRAAL_PW=... Graal404r2mac --server HOST:14900 --account NAME --server-name Login
Graal404r2mac --level some.nw                  # offline
```

## Not yet, or not known

- [ ] The ids handled, the empty 44 and the order of the messages after login: taken from the 4.11 Mac; the 4.04r2 Mac run did not record them.
- [ ] The Mac server-to-client switch for 4.04r2 (its profile row borrows the Windows set).
- [ ] The Mac install's files compared with 4.11 Mac's and 4.20r8's.
- [ ] The original's own icon: not extracted, so the Windows program has the default icon.
- [ ] A macOS build of this rebuild.
- [ ] The 3D mode.
- [ ] No side-by-side run against the real Mac 4.04r2; that is 0.0.2 work.
