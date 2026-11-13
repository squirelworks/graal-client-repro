# Graal 1.38 revision 1 (`GNW02070`)

The Graal 1.38 rev 1 client, rebuilt. Original: `Graal.exe`, 1,428,480
bytes, file date 2000-07-03, FileVersion 1.3.8.0, ProductVersion 1.38,
SHA-256 `36abc58a…`, from a copy of the official `graal138.zip` of
August 2000 (cut at 1 MB; the exe is complete). gs2lib lists
its token as 1.381 (`CLVER_1_381`). gcr's `graal-1.38-GNW22060` is the
earlier 1.38 (2000-06-23).

This is a 0.0.1 reproduction made from the 1.38 rebuild. Like 1.38's,
everything past the login and the start dialog is still the 2.05
behaviour.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

## What differs from the 1.38 rebuild

| | 1.38 rev 1 | 1.38 |
|---|---|---|
| Token | `GNW02070` (exe and wire) | `GNW22060` |
| File date | 2000-07-03 | 2000-06-23 |
| FileVersion | 1.3.8.0 (not bumped) | 1.3.8.0 |
| Receive dispatcher, GS1 table | the same (44 ids, 0 to 41, 43, 100; 109 commands) | |
| Start dialog, F1 window | the same forms | |
| Game window form | two controls 4 px apart from 1.38's | |
| New strings | a "Don't connect levels" option, and a web browser control (TWebBrowser) | |

Shared with the 1.38 rebuild: the generation-2 wire, the login line (id 0,
the token, the account and the password, no key byte, no language packet),
the connect dialog with one address, `PLI_ITEMTAKE`, board before name.

## Checked against the real client (lab, 2026-11-13)

In the Windows 10 lab VM, with no network, the real 1.38 rev 1 (on the
reconstructed install: this copy's exe and arrays.dat, the rest from
a 1.38 install) was started in "One Player Online" against a
capture server. Its first frame inflates to id 0, `GNW02070`, the account
and the password. The rebuild, built with Free Pascal and with Delphi 7,
sent the same bytes. The start dialogs match.

## Sources

The version facts come from graal_analysis: the build catalogue
(`archive-survey/build-catalogue.md`), the 1.33 to 1.39 version profiles
(`client-internals/version-profiles/`), `protocol/gserv-1999.md`, and the
lab captures of 1.21, 1.28 beta 2 and 1.3 test logged into their own
GServers. The 2.05 rebuild's own sources are listed in
`graal-2.05r2-GNW03081/README.md`.

## Where to put your Graal files

The program looks for files in its own folder, never above it. Copy the
contents of a 1.38 install next to `Graal138r1` (`levels/`, `pics1.png`
and the rest, as the install has them), or put a `graal-assets/` folder
there holding `1.38r1/` and `common/`. With nothing next to it,
it runs on its own built-in graphics and starter level. `--data DIR`
points at another folder.

## Build and run

```
scripts/build.sh graal-1.38r1-GNW02070
build/graal-1.38r1-GNW02070/Graal138r1r1                       # start screen
GRAAL_PW=... build/graal-1.38r1-GNW02070/Graal138r1r1 --server HOST:PORT --account NAME
build/graal-1.38r1-GNW02070/Graal138r1r1 --level levels/start1.graal --window
```

## Not yet (0.0.2)

- [ ] What rev 1 adds: the "Don't connect levels" option and whatever uses
  the web browser control.
- [ ] Everything still open in the 1.38 rebuild (the version's id sets and
  GS1 commands, prop encodings, local multiplayer, options).
