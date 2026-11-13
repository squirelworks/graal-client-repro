# Graal 2.1.0.0 (GNW31101)

A rebuild of the first public Graal 2.1 client (November 2001) in Delphi
(Object Pascal). Like the original it is a windowed program: it opens on a
start window with Training, the server list from the listserver, and login.
This is an early, hit-or-miss first release, built from the 2.1 test 3
rebuild.

**Login token: tested against the real client.** The original was run in
the lab (2026-11-13) and `GNW31101` was seen in its login on the wire; this
rebuild sends the same token.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

The program carries what the original's own `Graal.exe` carries (its start
window and server list forms and art, its Training levels, its icon and its
`headsconfig.txt`) and the whole 2.1.0.0 install, so it runs alone in an
empty folder. Put it at the top of a Graal install you own and the
install's files come first.

## What's new in v0.0.1

- [x] **Its own token.** Logs in with `GNW31101`, so a server treats it as
  2.1, not 2.05.
- [x] **The 2.1 server messages.** Ghost mode, ghost text and ghost icon
  (170, 173, 174), and the big map and minimap a server sets (171, 172).
- [x] **2.1 file messages.** Reads the mod time a server sends a 2.1 client
  in front of each file.
- [x] **Its own resources.** The 2.1.0.0 forms, Training levels, start art
  and `headsconfig.txt`, and the complete 2.1.0.0 install, with no files from
  other versions.
- [x] **The updater.** `GetPacks2100` reads the 2001 updater's `setup.ini`,
  fetches its `.pack` packages from a folder or over HTTP, unpacks them and
  keeps `setup/installed.db`, as the original setup program did. It rebuilds
  the 2.1.0.0 install byte for byte from the archived packages.
- [x] **Builds with Delphi 7** as well as Free Pascal.

## Not yet

- [ ] The seven GS1 commands 2.1.0.0 adds (`addstring`, `deletestring`,
  `insertstring`, `removestring`, `replacestring`, `play2`, `shoot`).
- [ ] Keeping and using files the server sends.
- [ ] The ghost icon on screen, and the minimap position a server sets.
- [ ] The reconnect dialog.
- [ ] Everything still open in 2.1 test 3: the start window layout, the
  tabbed options window, props 43 to 45 on screen, UDP message 27.
