# Graal 1.27 (`GSERV011`)

The Graal 1.27 client, rebuilt. Original: `Graal.exe` from the "Graal - The
adventure (V. 1.2.7)" InstallShield 3 package (disk set built 1999-11-27,
the exe stored as 1999-10-23), 1,065,472 bytes, MD5
`edced61412edfcf36bf29e2abda60d94`, no VERSIONINFO. New in this version (its
readme): English and German language files, `setstring`, `setbackpal`,
`setletters`, the `save[0]`-`save[9]` NPC variables, and the "don't show
decompression errors" option.

This is a 0.0.1 reproduction made from the 1.21 rebuild (by way of the 1.25
one) and changed where 1.27 is known to differ. Like
1.21's, everything past the login and the start dialog is still the 2.05
behaviour.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

## What differs from the 1.21 rebuild

| | 1.27 | 1.21 |
|---|---|---|
| Token | `GSERV011` | `GSERV007` |
| Server messages handled | 0 to 38 and 100 (40) | 0 to 29, 31 to 34 and 100 (35) |
| GS1 commands | 84, entry for entry 1.28 beta 2's: 1.25's 80 plus `showfile`, `setstring`, `setbackpal`, `setletters` | 71 |
| Start dialog, F1 window, icon | 1.27's own forms (it adds a message editor, a player list and a character editor form, and the VCL button and media-player bitmaps), from its exe | 1.21's |
| Character list | the 1.27 headsconfig.txt (28 entries, the same as 1.25's; "Ninji Knight" spelled as in this install) | 1.21's |
| Start dialog layout | the 1.28 beta 2 one: a language list, and One Player keeps the Nick Name row | no language list; One Player shows no panel |
| `nodecompressionerror=` option | in its F1 window (first build with it) | no |

Read from the binaries (graal_analysis `client-internals/gserv-125-127-builds.md`,
2026-11-13): the token is a string literal next to the default port; the
message set is the dispatcher's, the command count from
`tools/gs1-table-scan`. The 1.x rebuilds do not yet limit the server ids or
GS1 commands to their version's set, so the two middle rows change nothing
in the program yet (see "Not yet").

Shared with the 1.21 rebuild: the generation-2 wire (a u16be length and one
zlib stream per flush, no cipher, no key byte), the login line (id 0, the
token, the account and the password as GSTRINGs), no listserver (a connect
dialog with one address, port 14804), board before name, and
`PLI_ITEMDEL` for taken items.

## Checked against the real client (lab, 2026-11-13)

In the Windows 10 lab VM, with no network, the real 1.27 (its install laid
out from the package's groups) was started in "One Player Online" with the
default server and the `guest` account, against a capture server on 14804.
Its first frame inflates to id 0, `GSERV011`, `guest`, `guest`. The rebuild,
built with Free Pascal and with Delphi 7, sent the same bytes. The rebuild's
start dialog matches the real one (same form, pictures, mode list and the
default character). With the install next to it, the rebuild reads the
`language*.txt` files into the language list and the real client's
`graalconfig.txt` (mode, nick name, account), as the original does.

## Start dialog (0.0.3)

With no arguments on Windows the program shows the original's own start
dialog, built from the `TConnectFrame` form in `res/TCONNECTFRAME.dfm`
(`src/RealRes127.pas`, from `scripts/realres/extract_res.py`, shown by
`common/GVclForm.pas` and `common/GBetaStart.pas`). Start opens the game in a
window shaped as the `TAdventure` form. Elsewhere the shared start screen
stays.

## Sources

The version facts come from graal_analysis: the build catalogue
(`archive-survey/build-catalogue.md`), the 1.33 to 1.39 version profiles
(`client-internals/version-profiles/`), `protocol/gserv-1999.md`, and the
lab captures of 1.21, 1.28 beta 2 and 1.3 test logged into their own
GServers. The 2.05 rebuild's own sources are listed in
`graal-2.05r2-GNW03081/README.md`.

## Where to put your Graal files

The program looks for files in its own folder, never above it. Copy the
contents of a 1.27 install next to `Graal127` (`levels/`, `pics1.png`
and the rest, as the install has them), or put a `graal-assets/` folder
there holding `1.27/` and `common/`. With nothing next to it,
it runs on its own built-in graphics and starter level. `--data DIR`
points at another folder.

## Build and run

```
scripts/build.sh graal-1.27-GSERV011
build/graal-1.27-GSERV011/Graal127                       # start screen
GRAAL_PW=... build/graal-1.27-GSERV011/Graal127 --server HOST:PORT --account NAME
build/graal-1.27-GSERV011/Graal127 --level levels/start1.graal --window
```

## Not yet (0.0.2)

- [ ] The id sets 1.27 sends and handles: the rebuild still accepts every
  2.05 server id and its GS1 engine knows the 2.05 commands.
- [ ] The prop encodings checked one by one against 1.27 (its `save[0]`-`save[9]` NPC variables should be new NPC props; graal_analysis
  has the 1.21 and 1.28 beta 2 ranges only).
- [ ] The `nodecompressionerror=` option.
- [ ] `serveraddr=` as the real client writes it, in quotes: the rebuild
  shows the quotes (a shared fix for every 1.x build, `common/`).
- [ ] Server messages 35 to 38 (new by 1.25, still unnamed). UDP stays out: it came with 1.28 beta 2.
- [ ] Local 2 to 4 player modes, UDP peer data, and this version's options.
