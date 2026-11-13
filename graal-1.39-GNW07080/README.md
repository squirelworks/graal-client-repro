# Graal 1.39 (`GNW07080`)

The Graal 1.39 client, rebuilt. Original: `Graal.exe`, 1,448,960 bytes,
linked 2000-08-07, MD5 `62513ab884f1802a0bcd8114abe349b9`. New in this version: Profiles (ids 80, 81 and 75), a player-list options window, chat history, and new head-image handling.

This is a 0.0.1 reproduction: it was made from the 2.05 rev 2 rebuild in
this repo and changed where 1.39 is known to differ. Everything else
(drawing, walking, NPCs and GS1, items, combat, editor) is the 2.05
behaviour and has not been checked against 1.39 yet. Comments and
tests that name 2.05 were measured on 2.05.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

## What differs from the 2.05 rebuild

- **Generation 2 wire.** Every flush is a u16be length and one zlib stream,
  with no cipher and no inserted byte. The login line is id 0, the 8-byte
  token `GNW07080`, the account and the password (each a GSTRING),
  with no key byte and no language packet after it (test, from the lab
  captures of the GSERV builds).
- **Board before name.** A generation-2 server sends the warp, then
  `PLO_RAWDATA` + `PLO_BOARDPACKET`, then `PLO_LEVELNAME`. The level name
  that follows a fresh board keeps it; a link warp, where the name comes
  first, works as in 2.05.
- **No server list.** 1.39 had a connect dialog with one address,
  pre-filled with the official host and port 14900. The rebuild pre-fills
  `listserver.graal.in:14923` instead and shows it as the only row of the
  server page. `graalconfig.txt` next to the program (`serveraddr=HOST` or
  `HOST:PORT`, `serverport=PORT`) or `listserver.txt` (host, then port)
  replaces it.
- Items on the floor are taken with `PLI_ITEMTAKE` (32), which this version has.
- **Training** loads `levels/start1.graal` (or `levels/house1.graal`) when
  it lies next to the program, else the built-in starter level. There are
  no tutorial levels and no tutorial maps.

## Sources

The version facts come from graal_analysis: the build catalogue
(`archive-survey/build-catalogue.md`), the 1.33 to 1.39 version profiles
(`client-internals/version-profiles/`), `protocol/gserv-1999.md`, and the
lab captures of 1.21, 1.28 beta 2 and 1.3 test logged into their own
GServers. The 2.05 rebuild's own sources are listed in
`graal-2.05r2-GNW03081/README.md`.

## Where to put your Graal files

The program looks for files in its own folder, never above it. Copy the
contents of a 1.39 install next to `Graal139` (`levels/`, `pics1.png`
and the rest, as the install has them), or put a `graal-assets/` folder
there holding `1.39/` and `common/`. With nothing next to it,
it runs on its own built-in graphics and starter level. `--data DIR`
points at another folder.

## Build and run

```
scripts/build.sh graal-1.39-GNW07080
build/graal-1.39-GNW07080/Graal139                       # start screen
GRAAL_PW=... build/graal-1.39-GNW07080/Graal139 --server HOST:PORT --account NAME
build/graal-1.39-GNW07080/Graal139 --level levels/start1.graal --window
```

## Seihai secure login (not in the original)

Off by default, so the login is byte for byte the original's. With
`--secure-login auto` or `required` (or one word in `secure_login.txt` in
the shared settings folder), the account and the password go sealed to a
Seihai game server (version token `SEI00001`, graal-client-repro #148).
C1 carries the type byte of the classic login and this build's token, and
C2 stands in for the login line. Same code and settings as 2.31: see the 2.31 README,
"Seihai secure login". CI logs in once more with `--secure-login required`
(`scripts/loopback.sh`).

## Not yet (0.0.2)

- [ ] The id sets 1.39 sends and handles: the rebuild still accepts every
  2.05 server id and its GS1 engine knows the 2.05 commands.
- [ ] The prop encodings checked one by one against 1.39.
- [ ] Local 2 to 4 player modes, UDP peer data, and this version's options.
- [ ] A side-by-side run with the original under Wine.
