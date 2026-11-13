# Graal 1.39 revision 1 (`GNW07080`)

The Graal 1.39 rev 1 client, rebuilt. Original: `Graal.exe` from the
"Graal v1.39 - Dup" archive, 1,450,496 bytes, file date 2000-08-13,
FileVersion 1.3.9.1, SHA-256 `01bf1b1f…`. Its install's own readme is titled
"Graal V1.39 revision 1 Release Notes", and its `newfeatures139.txt` opens
with "v1.39rev1": the kills, deaths and online time of the current world in
a player's profile, `<applet>` tags blocked in PMs, a fix for transparent
heads after a 32-bit fullscreen switch, and PMs to more than 50 people no
longer saved to disk.

This is a 0.0.1 reproduction made from the 1.39 rebuild. Like 1.39's,
everything past the login and the start dialog is still the 2.05
behaviour.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

## What differs from the 1.39 rebuild

| | 1.39 rev 1 | 1.39 (gcr's `graal-1.39-GNW07080`) |
|---|---|---|
| Token | `GNW07080` (the same) | `GNW07080` |
| FileVersion | 1.3.9.1 | 1.3.8.0 (not bumped) |
| File date | 2000-08-13 | 2000-08-07 |
| Receive dispatcher, GS1 table | the same (45 ids; 111 commands) | 45 ids; 111 commands |
| Start dialog | the same form | |
| Game window form | one scroll bar of the editor panel sits 8 px further left | |
| New strings | "Kills:", "Deaths:", "Online time:" (profile), `(keynum)`, `keydown` | |

The gs2lib version table lists `GNW12080` for "1.391". This build, whose
install calls it 1.39 rev 1, builds `GNW07080` one character at a time, and
that is its only token builder; it sent `GNW07080` on the wire (below).
No held binary sends `GNW12080` (graal_analysis
`client-internals/graal2002-and-140-builds.md`).

Shared with the 1.39 rebuild: the generation-2 wire (no cipher, no key
byte, no language packet), the login line (id 0, the token, the account
and the password as GSTRINGs), the connect dialog with one address,
`PLI_ITEMTAKE`, board before name.

## Checked against the real client (lab, 2026-11-13)

In the Windows 10 lab VM, with no network, the real 1.39 rev 1 (from its own
install) was started in "One Player Online" against a capture server. Its
first frame inflates to id 0, `GNW07080`, the account and the password, with
no key byte. The rebuild, built with Free Pascal and with Delphi 7, sent the
same bytes.

## Sources

The version facts come from graal_analysis: the build catalogue
(`archive-survey/build-catalogue.md`), the 1.33 to 1.39 version profiles
(`client-internals/version-profiles/`), `protocol/gserv-1999.md`, and the
lab captures of 1.21, 1.28 beta 2 and 1.3 test logged into their own
GServers. The 2.05 rebuild's own sources are listed in
`graal-2.05r2-GNW03081/README.md`.

## Where to put your Graal files

The program looks for files in its own folder, never above it. Copy the
contents of a 1.39 rev 1 install next to `Graal139r1` (`levels/`, `pics1.png`
and the rest, as the install has them), or put a `graal-assets/` folder
there holding `1.39r1/` and `common/`. With nothing next to it,
it runs on its own built-in graphics and starter level. `--data DIR`
points at another folder.

## Build and run

```
scripts/build.sh graal-1.39r1-GNW07080
build/graal-1.39r1-GNW07080/Graal139r1                       # start screen
GRAAL_PW=... build/graal-1.39r1-GNW07080/Graal139r1 --server HOST:PORT --account NAME
build/graal-1.39r1-GNW07080/Graal139r1 --level levels/start1.graal --window
```

## Not yet (0.0.2)

- [ ] What rev 1 adds: the profile window with kills, deaths and online
  time (the rebuild has no profile window yet, as 1.39's), the blocked
  `<applet>` tags in PMs, and PMs to more than 50 people not saved.
- [ ] The id sets 1.39 rev 1 sends and handles: the rebuild still accepts
  every 2.05 server id and its GS1 engine knows the 2.05 commands.
- [ ] The prop encodings checked one by one.
- [ ] Local 2 to 4 player modes and this version's options.
