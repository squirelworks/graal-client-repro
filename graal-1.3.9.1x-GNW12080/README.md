# Graal 1.3.9.1x (`GNW12080`), inferred

A client that sends `GNW12080`, the token gs2lib's version table lists as
1.391 (`CLVER_1_391`, 12 Aug 2000). **No binary that sends it is held.**
The only FileVersion 1.3.9.1 exe of that week, the "1.39 revision 1" of
13 Aug 2000, sends 1.39's `GNW07080` (read from the exe and seen on the
wire, see `graal-1.39r1-GNW07080`). A build with `GNW12080` was recorded by
the server software of the time, so it most likely existed and was lost;
Graal's versioning in 2000 was loose (two different exes carry FileVersion
1.3.9.1, and 1.39 itself says 1.3.8.0).

This folder is the 1.39 rev 1 rebuild with that one token changed, so a
server can be tested with the 1.391 login. Everything else, the forms,
icon and behaviour, is 1.39 rev 1's: the date stamps are one day apart and
the dispatcher and command table did not change between 1.39 and 1.40, so
1.39 rev 1 is the nearest real build. The `x` in the name marks it as
inferred.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

## What differs from the 1.39 rev 1 rebuild

| | 1.3.9.1x | 1.39 rev 1 |
|---|---|---|
| Token | `GNW12080` (gs2lib, inferred) | `GNW07080` (exe and wire) |
| Build label and title | `1.3.9.1x`, "Graal 1.3.9.1x" | `1.39r1` |

The login is the generation-2 line of 1.39 rev 1 (id 0, the token, the
account and the password, no key byte, no language packet).

## Checks for 0.0.1

- Builds with Free Pascal on Windows; `Test1391x`, `TestEditor1391x` and
  `TestSoundMap1391x` pass with no leaks.
- `scripts/loopback.sh` against seihai-gserver: two copies log in (the
  server reads `GNW12080` as an unknown generation-2 build and serves the
  1.39 shape, which is this build's), the second sees the first.
- There is no real client to compare with.

## Sources

The version facts come from graal_analysis: the build catalogue
(`archive-survey/build-catalogue.md`), the 1.33 to 1.39 version profiles
(`client-internals/version-profiles/`), `protocol/gserv-1999.md`, and the
lab captures of 1.21, 1.28 beta 2 and 1.3 test logged into their own
GServers. The 2.05 rebuild's own sources are listed in
`graal-2.05r2-GNW03081/README.md`.

## Where to put your Graal files

The program looks for files in its own folder, never above it. Copy the
contents of a 1.39 install next to `Graal1391x` (`levels/`, `pics1.png`
and the rest, as the install has them), or put a `graal-assets/` folder
there holding `1.3.9.1x/` and `common/`. With nothing next to it,
it runs on its own built-in graphics and starter level. `--data DIR`
points at another folder.

## Build and run

```
scripts/build.sh graal-1.3.9.1x-GNW12080
build/graal-1.3.9.1x-GNW12080/Graal1391x                       # start screen
GRAAL_PW=... build/graal-1.3.9.1x-GNW12080/Graal1391x --server HOST:PORT --account NAME
build/graal-1.3.9.1x-GNW12080/Graal1391x --level levels/start1.graal --window
```

## Not yet (0.0.2)

- [ ] A real `GNW12080` binary to check against, if one turns up.
- [ ] Everything still open in the 1.39 rev 1 rebuild (its profile window,
  the version's id sets and GS1 commands, the prop encodings).
