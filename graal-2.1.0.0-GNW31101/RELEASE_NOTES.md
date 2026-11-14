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

## What's new in v0.0.5

- [x] **Sword hits as this build judges them.** A sword tip exactly 2 tiles to the side now hits (every build from 1.21 to 2.31 includes the edge). Read in the binaries for seihai-core #28 (#302).
- [x] **Spin attack.** With the spin status (STATUS bit 0x40, from the server or the spin attack item), pressing S again while the swing still plays cuts it off and plays `spin` (13 ticks, then idle); S during the spin is ignored. Modelled on the live 2.05 and 2.22 runs. What the spin hits (a box round the player here) is not yet checked on the real client (#302).
- [x] **Laying items.** Hold S and press A to pick an item to lay; it shows over the head. A again with S held picks the next item, A alone lays it in front, and an arrow, S or D leaves without laying. Rupees, bombs, darts, a heart, the glove, a stock sword or shield and the spin can be laid, at the 2.05 costs; online a laid floor item is sent as `PLI_ITEMADD` (12). A custom sword or shield picture is not laid yet, and water in front is not told apart from land (#302).
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
  the 2.1.0.0 install byte for byte from copies of the official packages.
- [x] **Builds with Delphi 7** as well as Free Pascal.

## Not yet

- [ ] The seven GS1 commands 2.1.0.0 adds (`addstring`, `deletestring`,
  `insertstring`, `removestring`, `replacestring`, `play2`, `shoot`).
- [ ] Keeping and using files the server sends.
- [ ] The ghost icon on screen, and the minimap position a server sets.
- [ ] The reconnect dialog.
- [ ] Everything still open in 2.1 test 3: the start window layout, the
  tabbed options window, props 43 to 45 on screen, UDP message 27.
