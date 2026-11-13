# Graal 3.01 (`G3D27063`)

The 3.01 client, rebuilt. The original is the Linux 3.01, a Torque build of the C++ client (the token's date stamp, 27 June 2003, is one day before the 2.2 Windows token `GNW28063`). This folder starts
from `graal-3.04-G3D03014` and changes what is known of 3.01. It was never run in
the lab, so everything not listed below is the sibling's. This
is the 0.0.1 reproduction: hit or miss.

## Sources

From [graal_analysis](https://github.com/squirelworks/graal_analysis), not
from decompiled code:

| Area | Notes |
|---|---|
| Token | `client-internals/version-token-catalogue.md`, `protocol/login-tokens-3x-7x.md` |
| Client type 4 and the gen-4 codec | `protocol/login-tokens-3x-7x.md` ("Where the token sits"), `protocol/codec-and-framing.md` |
| Everything carried over | `../graal-3.04-G3D03014/README.md` (the 3.04 lab run, `version-profiles/lab-304-linux-2026-10-30.md`) |

## What differs from the 3.04 rebuild

| | 3.04 | 3.01 (this folder) |
|---|---|---|
| Game token | `G3D03014` | `G3D27063` |
| Client type (first login byte) | 5 | 4 |
| Game link after login | gen 5: compression byte, then a body that is raw, zlib or bz2 | gen 4: no compression byte, every body bz2, the first 4 dwords XORed with the same LCG |

Everything else is 3.04's: the 79 server ids handled, the first props
(`linux`, code page 1250), no tamper check, no 24 over TCP, the 800 × 600
view, and the listserver step (`G3D30123` + `newmain`), whose link is
kept on gen 5. gs2lib and GServer-v2 put 3.0 and 3.01 with the 2.19 to
2.21 clients as client type 4; that, and the token, are all that is known
of this build's wire.

## Units

As in 3.04, with the suffix `301`: `Protocol301`, `GraalClient`, `Adventure`, `Graal301.dpr`, `Game301Lib.lpr`, `ListServer301`, `StartScreen301`, `RunMode`.

## Running it

### On the Torque engine (Linux, Windows, macOS)

The Linux zip holds `graal304-torque` and `libGame301Lib.so`, the Windows zip
`graal304-torque.exe` and `Game301Lib.dll`, and the macOS zips
`graal304-torque.app` with `libGame301Lib.dylib` inside it. Copy them into the
root of a 3.01 install (the folder with `main.cs`) and start
`graal304-torque`. When it finds only one game library beside it, it runs
that one, so a 3.01 zip runs 3.01's game; `--game FILE` picks another. It
runs the install's own scripts on the rebuilt Torque engine
(`common/torque/guigraal`), with the game drawn inside the `Adventure`
control. Prefs go to `~/.graal304-torque`. On Linux it needs an X11 display.

### The Pascal program

Put `Graal301` in the root of a 3.01 install and start it with no arguments
for the start screen, or:

```
GRAAL_PW=... Graal301 --server HOST:PORT --account NAME
Graal301 --level some.nw                  # offline
```

## Not yet, or not known

- [ ] A lab run of the real 3.01 (Linux lab VM): see `G3D27063` and type 4 on the wire, check the gen-4 frames both ways, and whether the listserver link is gen 4 or gen 5.
- [ ] Which server ids 3.01 handles and what it sends; 3.04's are used.
- [ ] Its install layout (3.04's is assumed, so the 3.04 game methods are registered, not 3.153's).
- [ ] Its window size and menus (3.04's 800 × 600 is assumed).
- [ ] Everything still missing from the 3.04 rebuild.
- [ ] No side-by-side run against the real 3.01; that is 0.0.2 work.
