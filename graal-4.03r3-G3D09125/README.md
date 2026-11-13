# Graal 4.03r3 (`G3D09125`)

The 4.03r3 client, rebuilt. The original is the Windows 4.03r3 (4.0.3.3; the public list calls it 4.03.4), the 4.x engine behind a custom packer in the `Graal4Setup.exe` download (token date stamp 9 December 2005). Its token was read from the engine image the packer unpacks into memory under Wine, where it then stops on a DirectDraw error before it connects. This folder starts
from `graal-4.20r8-G3D20126` and changes what is known of 4.03r3. It was never run in
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

| | 4.20r8 | 4.03r3 (this folder) |
|---|---|---|
| Game token | `G3D20126` | `G3D09125` |
| Server ids handled | 101 | 98: 4.04r2's set, with no 107, 108 or 196 (it is older than 4.04r2) |

The Login session, 178, the messages after login, X2/Y2 walking and 24
every 5.145 s are as in 4.20r8 (and 4.04r2, whose lab runs they were timed on). The
4.20r8 launcher shell (`Shell420`, for the 4.2.0.8 engine host) is not
carried over.

## Units

As in 4.20r8, with the suffix `403r3`: `Protocol403r3`, `GraalClient`, `Adventure`, `Graal403r3.dpr`, `ListServer403r3`, `StartScreen403r3`, `RunMode`.

## Running it

Put `Graal403r3` in the root of a 4.03r3 install and start it with no arguments
for the start screen. It finds the install's files from there, or from
`graal-assets/…` next to it (its own folder, then `4.20r8`, then `common`).
Start asks `listserver.graal.in` on 14922 for a list first (a
`listserver.txt` next to the program names another); the install's
`license/license.graal` Login host is added as a row named `Login`.

```
GRAAL_PW=... Graal403r3 --server HOST:PORT --account NAME
GRAAL_PW=... Graal403r3 --server HOST:14900 --account NAME --server-name Login
Graal403r3 --level some.nw                  # offline
```

## Not yet, or not known

- [ ] A lab run of the real 4.03r3 (Windows lab VM; the packed `Graal4Setup.exe` stops on a DirectDraw error under Wine, so it needs a real Windows VM with DirectDraw): see `G3D09125` on the wire, and check the login line, the messages after login and the ids handled, all taken from 4.20r8 and 4.04r2 so far.
- [ ] Whether 4.03r3 handles 107, 108 and 196; 4.04r2's set (without them) is used.
- [ ] The install's files compared with 4.20r8's.
- [ ] The original's own icon and resources (inside the packed exe): not extracted, so the Windows program has the default icon.
- [ ] The 3D mode.
- [ ] Everything still missing from the 4.20r8 rebuild.
- [ ] No side-by-side run against the real 4.03r3; that is 0.0.2 work.
