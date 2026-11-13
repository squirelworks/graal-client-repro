# Graal 2.1.0.0 (`GNW31101`)

The first public Graal 2.1 client, rebuilt. Original: `Graal.exe` 2.1.0.0,
1,771,008 bytes (SHA-256 `3b5af9f2…`, file date 2001-11-14, FileVersion
2.1.0.0), Delphi with DelphiX and zlib. It was never shipped as an
installer: the download was a small updater that fetched the client in
packages (see "The updater" below). Its window is titled "Graal 2001".

This folder starts as a copy of `graal-2.1t3-GNW03081` (2.1 test 3, the
nearest build with a rebuild) and is changed where 2.1.0.0 is known to
differ. Version 0.0.1 carries the differences a server or a player sees
first; the rest is listed under "Not yet".

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

## What differs from the 2.1 test 3 rebuild

| | 2.1.0.0 | 2.1 test 3 |
|---|---|---|
| Token | `GNW31101` | `GNW03081` (2.05's) |
| How a server treats it | as 2.1 (gs2lib `CLVER_2_1`): file mod times, `.png` defaults, the 2.1 login extras | as 2.05 |
| Server messages handled | 66 (bound `0xAE`): test 3's 61 and 170 to 174 | 61 (bound `0xA9`) |
| GS1 commands | 168: test 3's 161, `addstring`, `deletestring`, `insertstring`, `removestring`, `replacestring`, `play2`, `shoot` | 161 |
| Reconnect dialog | Reconnect and Close only | adds "Play offline" |
| Program resources | its own forms, Training levels (4 of 13 differ from test 3's), start art and `headsconfig.txt` | test 3's |
| Install | the whole 2.1.0.0 install (392 files) | test 3's plus 127 stand-ins |

How each row was read (2026-11-13): the token with the character-immediate
scan and then on the wire (below); the message count from the exe's receive
dispatcher, the same method as graal_analysis
`version-profiles/plo-handled-ids-by-build.tsv`; the command list with
graal_analysis `tools/gs1-table-scan` in `table` mode. The 2.1.0.0 set of
server messages is the Graal 2002 ver10 set plus ids 2, 4, 17, 18, 154 and
155 (baddies, the chest, horses), which ver10 routes to its default branch.

### The new server messages

| Id | gs2lib name | What the rebuild does |
|---|---|---|
| 170 | GHOSTMODE | a flag: the player is a ghost (free accounts walk as ghosts in 2.1) |
| 171 | BIGMAP | "file,file,x,y": sets the big map (the M key) to that text grid and picture |
| 172 | MINIMAP | the same for the minimap |
| 173 | GHOSTTEXT | text shown at the lower right of the view in ghost mode |
| 174 | GHOSTICON | a flag: show the ghost icon |

GServer-v2 sends its `bigmap=` and `minimap=` options at login with the text
file first, and its `setmap` with the picture first; the rebuild takes the
field that ends in `.txt` as the text file, so both work.

A 2.1 client also gets each file's mod time in `PLO_FILE` (102) ahead of the
name. The rebuild reads it and logs the file; keeping downloaded files is
under "Not yet".

## Checked against the real client (lab, 2026-11-13)

In the Windows 10 lab VM, with no network, the real 2.1.0.0 and this rebuild
were pointed at a capture server (`tools` of the lab notes; a listserver that
lists one server, and a game port that logs the first frame):

- **Listserver.** The real client looks up its built-in listserver host (the
  lab answered every lookup with loopback) and connects to port 14922. Its first frame inflates to id 0 `newmain`, then
  id 1 with the account and an empty password, as 2.1 test 3. The rebuild
  sends the same two messages.
- **Server list.** The real client showed the one listed server in its
  "Server list" window and connected on Connect.
- **Login.** The real client's first game frame inflates to type 0, its key,
  `GNW31101`, the account and the password, then LANGUAGE (37) and one more
  message in the gen-3 cipher. The rebuild sends type 0, its key,
  `GNW31101`, the account, the password and LANGUAGE. Both the Free Pascal
  and the Delphi 7 builds were checked.

## The listserver

Default: `listserver.graal.in`, port 14923, as the other 2.x rebuilds: the
original's own host and port (above) belong to the 2001 service. A
`listserver.txt` next to the program (host on the first line, port on the
second) names another.

## Where it finds its files

The program sits at the top of its folder and reads only that folder:

1. the folder itself, laid out as an install (`levels/`, `pics1.png`, ...),
   or the folder given with `--data`;
2. `graal-assets/2.1.0.0/`, then `graal-assets/2.1t3/` and
   `graal-assets/2.05r2/`;
3. `graal-assets/common/`.

Then the files of the 2.1.0.0 install it carries (`src/res/Graal2100Install.res`,
listed in `src/res/install-manifest.txt`, packed by
`scripts/res/install_res.py` from the install the updater builds). Unlike
test 3's folder, nothing is a stand-in from another version: the 2.1.0.0
install is complete.

## The updater

2.1.0.0 came from a small setup program (built on the Cygwin setup of 2001),
not an installer. It read a package list, `setup.ini`, from a mirror and
fetched the packages it names; each package (`.pack`) is a tar.gz archive
with another name. Five packages make the 2.1.0.0 install:

| Component | Version | Package | What it holds |
|---|---|---|---|
| Executable | 2.1.0-0 | `mainexe_2100.pack` | `Graal.exe`, `newfeatures2001.txt` |
| Main | 1.0.1-0 | `main_1010.pack` | sheets, arrays, maps, language files, tile objects, readme |
| Levels | 1.0.0-4 | `levels_1004.pack` | `levels/` (ganis, heads, bodies, Training, ...) |
| Sounds | 1.0.0-3 | `sounds_1003.pack` | `sounds/`, `levels/midis/` |
| Developer (optional, `@ -Developer`) | 1.0.0-4 | `dev_1004.pack` | GraalShop, gif2mng, the level generator |

The program kept what it installed in `setup/installed.db` (the line
`INSTALLED.DB 2`, then `name package 0` for each component) and fetched a
component again when `setup.ini` named a newer package.

`GetPacks2100` (in `src/`) does the same from the command line:

```
GetPacks2100 --site FOLDER|http://HOST[:PORT]/PATH [--root DIR] [--developer] [--list]
```

It reads `setup.ini` from the site, fetches each component that is missing
or newer (a folder, or HTTP/1.0 GET as the original), unpacks it with its own
gunzip and tar reader, refuses paths that leave the install folder, and
writes `setup/installed.db`. On copies of the five official packages it rebuilds the
2.1.0.0 install byte for byte (392 files), with Free Pascal and with
Delphi 7, and a second run fetches nothing. It is not named "setup": Windows
treats such a name as an installer and asks for administrator rights.

## Builds

- Free Pascal (`scripts/build.sh`): `Graal2100`, `GetPacks2100` and the
  tests.
- Delphi 7, in the lab VM (2026-11-13): `Graal2100`, `GetPacks2100` and
  `TestPacks2100` build, as #245 does for 2.05 rev 2, 1.1 and 2.31:

  ```
  dcc32 -B -Q -U..\..\common;..\src;..\src\editor;<Lib> -I..\..\common;<Lib> -R..\..\common;<Lib> -O<Lib> -E<out> -N<out> Graal2100.dpr
  ```

  The units this folder copied from 2.1 test 3 needed the #245 fixes: the
  `in` paths with backslashes, `GetTickCount` under Delphi in the baddies,
  and backslash `{$R}` paths for Delphi's linker.

## Checks for 0.0.1

- Builds with Free Pascal on Windows; `Test2100`, `TestEditor2100`,
  `TestSoundMap2100` and `TestPacks2100` pass with no leaks.
- Delphi 7 builds, and its `GetPacks2100` and login match the Free Pascal
  build's (lab VM).
- The lab wire check above.

## Not yet (0.0.2)

- [ ] The seven GS1 commands 2.1.0.0 adds (`addstring`, `deletestring`,
  `insertstring`, `removestring`, `replacestring`, `play2`, `shoot`). They
  need a per-build command table in `common/GGs1.pas`; the shared table is
  2.1 test 3's.
- [ ] Keep files the server sends (`PLO_FILE`) and use them, as 2.17.1 does.
- [ ] The ghost icon (its place on screen is not known) and the ghost
  walking rules.
- [ ] The minimap position from BIGMAP / MINIMAP's x and y.
- [ ] The third message of the real login frame (after LANGUAGE), which the
  lab did not decode.
- [ ] The reconnect dialog (the rebuild has none; 2.1.0.0's has no "Play
  offline").
- [ ] The test 3 items that are still open: the start window layout, the
  tabbed options window, props 43 to 45 on screen, UDP message 27.
