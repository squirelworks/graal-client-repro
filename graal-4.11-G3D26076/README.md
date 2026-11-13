# Graal 4.11 (`G3D26076`)

The 4.11 client, rebuilt. The original is the Windows 4.11 (4.1.1.0), the 4.x engine behind the same custom packer as 4.03r3 (token date stamp 26 July 2006; the Mac and Linux 4.11 builds send other tokens, `G3D27076` and `G3D28076`). Its token was read from the unpacked engine image in memory and matches the public list. This folder starts
from `graal-4.20r8-G3D20126` and changes what is known of 4.11. It was never run in
the lab, so everything not listed below is the sibling's. This
is the 0.0.1 reproduction: hit or miss.

## Sources

From [graal_analysis](https://github.com/squirelworks/graal_analysis), not
from decompiled code:

| Area | Notes |
|---|---|
| Token | `client-internals/version-token-catalogue.md`, `protocol/login-tokens-3x-7x.md` |
| Login server, login line, ids handled | `protocol/v4x-clients.md`, `version-profiles/4.04-4.20.toml` |
| What the real client sends (the 4.04r2 and 4.20r8 runs, taken to hold) | `client-internals/live-behaviour-404.md` |
| Everything carried over | the 4.20r8, 4.04r2, 3.153 and 2.22 folder READMEs |

## What differs from the 4.20r8 rebuild

| | 4.20r8 | 4.11 (this folder) |
|---|---|---|
| Game token | `G3D20126` | `G3D26076` |

The Login session, 178, the messages after login, X2/Y2 walking and 24
every 5.145 s are as in 4.20r8 (and 4.04r2, whose lab runs they were timed on). The
4.20r8 launcher shell (`Shell420`, for the 4.2.0.8 engine host) is not
carried over.

## Units

As in 4.20r8, with the suffix `411`: `Protocol411`, `GraalClient`, `Adventure`, `Graal411.dpr`, `ListServer411`, `StartScreen411`, `RunMode`.

## Running it

Put `Graal411` in the root of a 4.11 install and start it with no arguments
for the start screen. It finds the install's files from there, or from
`graal-assets/…` next to it (its own folder, then `4.20r8`, then `common`).
Start asks `listserver.graal.in` on 14922 for a list first (a
`listserver.txt` next to the program names another); the install's
`license/license.graal` Login host is added as a row named `Login`.

```
GRAAL_PW=... Graal411 --server HOST:PORT --account NAME
GRAAL_PW=... Graal411 --server HOST:14900 --account NAME --server-name Login
Graal411 --level some.nw                  # offline
```

## Not yet, or not known

- [ ] A lab run of the real 4.11 (Windows lab VM; the packed `Graal4Setup.exe` stops on a DirectDraw error under Wine, so it needs a real Windows VM with DirectDraw): see `G3D26076` on the wire, and check the login line, the messages after login and the ids handled, all taken from 4.20r8 and 4.04r2 so far.
- [ ] The server ids 4.11 handles; 4.20r8's 101 are used.
- [ ] The install's files compared with 4.20r8's.
- [ ] The original's own icon and resources (inside the packed exe): not extracted, so the Windows program has the default icon.
- [ ] The 3D mode.
- [ ] Everything still missing from the 4.20r8 rebuild.
- [ ] No side-by-side run against the real 4.11; that is 0.0.2 work.
