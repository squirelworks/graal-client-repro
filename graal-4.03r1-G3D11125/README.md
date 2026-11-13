# Graal 4.03r1 (`G3D11125`)

The 4.03r1 client, rebuilt. The original is the Linux 4.03r1, one program built from the 4.x engine (token date stamp 11 December 2005). This folder starts
from `graal-4.20r8-G3D20126` and changes what is known of 4.03r1. It was never run in
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

| | 4.20r8 | 4.03r1 (this folder) |
|---|---|---|
| Game token | `G3D20126` | `G3D11125` |
| Login line platform | `win` | `linux`, three machine fields sent empty (the Linux 4.x line is not read; the name is the Linux 6.x clients') |
| OSTYPE, code page | `wind`, 1252 (assumed) | `linux`, 1250 (the Linux 3.04's lab values, assumed) |
| 44 (in the login burst and the answer to 182) | the program's name | empty, as the Mac 4.11 sent it (taken for Linux) |
| Server ids handled | 101 | 98: 4.04r2's set, with no 107, 108 or 196 (it is older than 4.04r2) |

The Login session, 178, the messages after login, X2/Y2 walking and 24
every 5.145 s are as in 4.20r8 (and 4.04r2, whose lab runs they were timed on). The
4.20r8 launcher shell (`Shell420`, for the 4.2.0.8 engine host) is not
carried over.

## Units

As in 4.20r8, with the suffix `403r1`: `Protocol403r1`, `GraalClient`, `Adventure`, `Graal403r1.dpr`, `ListServer403r1`, `StartScreen403r1`, `RunMode`.

## Running it

Put `Graal403r1` in the root of a 4.03r1 install and start it with no arguments
for the start screen. It finds the install's files from there, or from
`graal-assets/…` next to it (its own folder, then `4.20r8`, then `common`).
Start asks `listserver.graal.in` on 14922 for a list first (a
`listserver.txt` next to the program names another); the install's
`license/license.graal` Login host is added as a row named `Login`.

```
GRAAL_PW=... Graal403r1 --server HOST:PORT --account NAME
GRAAL_PW=... Graal403r1 --server HOST:14900 --account NAME --server-name Login
Graal403r1 --level some.nw                  # offline
```

## Not yet, or not known

- [ ] A lab run of the real 4.03r1 (Linux lab VM): see `G3D11125` on the wire, and check the login line, the messages after login and the ids handled, all taken from 4.20r8 and 4.04r2 so far.
- [ ] Whether 4.03r1 handles 107, 108 and 196; 4.04r2's set (without them) is used.
- [ ] The install's files compared with 4.20r8's.
- [ ] The original's own icon and resources: not extracted, so the Windows program has the default icon.
- [ ] The 3D mode.
- [ ] Everything still missing from the 4.20r8 rebuild.
- [ ] No side-by-side run against the real 4.03r1; that is 0.0.2 work.
