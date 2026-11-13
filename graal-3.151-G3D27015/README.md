# Graal 3.151 (`G3D27015`)

The 3.151 client, rebuilt. The original is the Linux 3.151, a Torque build of the C++ client between 3.04 (Linux) and 3.153 (Mac); its token is one day before 3.153's `G3D28015`, and its install has the same `languages3D` / `levels3d` / `scripts*` layout as the Mac 3.153. This folder starts
from `graal-3.153-G3D28015` and changes what is known of 3.151. It was never run in
the lab, so everything not listed below is the sibling's. This
is the 0.0.1 reproduction: hit or miss.

## Sources

From [graal_analysis](https://github.com/squirelworks/graal_analysis), not
from decompiled code:

| Area | Notes |
|---|---|
| Token | `client-internals/version-token-catalogue.md`, `protocol/login-tokens-3x-7x.md` |
| Install layout (same as 3.153), the home folder `~/.graal` | `protocol/v3x-clients.md`, `torque/engine-and-formats.md` |
| Everything carried over | `../graal-3.153-G3D28015/README.md`, `../graal-3.04-G3D03014/README.md` |

## What differs from the 3.153 rebuild

| | 3.153 | 3.151 (this folder) |
|---|---|---|
| Game token | `G3D28015` | `G3D27015` |
| OSTYPE prop | `mac` | `linux` (3.04's Linux value) |
| View | 640 × 480 (assumed) | 800 × 600 (3.04's Linux window, assumed) |

The 2.31 wire on gen 5, the 88 server ids, the listserver step, the login
frame and no tamper check are 3.153's.

## Units

As in 3.153, with the suffix `3151`: `Protocol3151`, `GraalClient`, `Adventure`, `Graal3151.dpr`, `Game3151Lib.lpr`, `ListServer3151`, `StartScreen3151`, `RunMode`.

## Running it

### On the Torque engine (Linux, Windows, macOS)

The Linux zip holds `graal304-torque` and `libGame3151Lib.so`, the Windows zip
`graal304-torque.exe` and `Game3151Lib.dll`, and the macOS zips
`graal304-torque.app` with `libGame3151Lib.dylib` inside it. Copy them into the
root of a 3.151 install (the folder with `main.cs`) and start
`graal304-torque`. When it finds only one game library beside it, it runs
that one, so a 3.151 zip runs 3.151's game; `--game FILE` picks another. It
runs the install's own scripts on the rebuilt Torque engine
(`common/torque/guigraal`), with the game drawn inside the `Adventure`
control. Prefs go to `~/.graal304-torque`. On Linux it needs an X11 display.

### The Pascal program

Put `Graal3151` in the root of a 3.151 install and start it with no arguments
for the start screen, or:

```
GRAAL_PW=... Graal3151 --server HOST:PORT --account NAME
Graal3151 --level some.nw                  # offline
```

## Not yet, or not known

- [ ] A lab run of the real 3.151 (Linux lab VM): see `G3D27015` on the wire, and check the ids handled, the first props and the window size, all taken from 3.153 and 3.04 so far.
- [ ] The intact 3.151 install's files compared with 3.153's (the first copy in the archive was damaged by an ASCII-mode transfer).
- [ ] Everything still missing from the 3.153 rebuild.
- [ ] No side-by-side run against the real 3.151; that is 0.0.2 work.
