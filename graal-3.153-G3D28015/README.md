# Graal 3.153 (`G3D28015`)

The 3.153 client, rebuilt. The original is the Mac OS X (PowerPC, Carbon)
build of the Torque C++ client, February 2005. On the wire it is the
Windows 2.31 client with its own token. This folder starts from
`graal-3.04-G3D03014` and changes what the notes read from the 3.153
binary. 3.153 was never run in the lab, so where its behaviour is not read
from the binary, the 3.04 lab run is taken to hold. This is the 0.0.1
reproduction: hit or miss.

## Sources

From [graal_analysis](https://github.com/squirelworks/graal_analysis), not
from decompiled code:

| Area | Notes |
|---|---|
| Token, listserver, licence file, ids handled | `protocol/v3x-clients.md` |
| Sent ids, props, features | `version-profiles/3.04-3.153.md` and `.toml` |
| Wire behaviour taken from 3.04 | `version-profiles/lab-304-linux-2026-10-30.md` |
| Everything carried over | `../graal-3.04-G3D03014/README.md`, `../graal-2.22-GNW03014/README.md` |

## What differs from the 3.04 rebuild

| | 3.04 | 3.153 (this folder) |
|---|---|---|
| Game token | `G3D03014` (2.22's date) | `G3D28015` (2.31's date) |
| OSTYPE prop | `linux` | `mac` |
| Server ids handled | 79 | 88: no 44; adds 67, 74, 82, 104, 131 to 134, 187, 189 |

Listserver (`G3D30123`), the licence file, the login frame, no tamper
check and no 24 over TCP are as in 3.04.

## Units

As in 3.04, with the suffix `3153`: `Protocol3153`, `GraalClient`,
`Adventure`, `Graal3153.dpr`, `ListServer3153`, `StartScreen3153`, `RunMode`.

## Running it

Put `Graal3153` in the root of a 3.153 install and start it with no
arguments for the start screen. It finds the install's files from there,
or from `graal-assets/3.153/` and `graal-assets/common/` next to it.

```
GRAAL_PW=... Graal3153 --server HOST:PORT --account NAME
Graal3153 --level some.nw                  # offline
```

## Not yet, or not known

- The ids 3.153 handles beyond 3.04 are accepted and ignored: 67 (folder
  log), 74 (RC chat), 82 (server text), 104, 131 to 134 (class and gani
  scripts), 187 and 189 (precise movement).
- What 3.153 sends beyond 3.04: 46 ENTERLEVEL, 50, the RC file browser,
  152/154 text, 155/156 uploads, 157/158 gani and script requests; the
  precise-move props (X2, Y2, Z2).
- The 3D mode (Torque on UDP, the listed port + 1, `Graal3D` protocol 19).
- 3.153's own login frame and first props are not captured; 3.04's are used.
- The code page prop (1250) is 3.04's lab value.
- Everything still missing from the 3.04 rebuild.
- No side-by-side run against the real 3.153; that is 0.0.2 work.
