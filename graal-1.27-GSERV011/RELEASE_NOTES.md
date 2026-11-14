# Graal 1.27 (GSERV011), 0.0.1

A first rebuild of the Graal 1.27 client (October 1999) in Delphi (Object
Pascal), for Linux and Windows, made from the 1.21 rebuild. It logs in the
way 1.27 did and plays a level offline. It is early and many parts still
behave like a later Graal: see "Not yet".

**Login token: tested against the real client.** The original was run in
the lab (2026-11-13) and `GSERV011` was seen in its login on the wire; this
rebuild sends the same login bytes.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

Apart from the start dialog, the forms and the icon, which are taken from
the real Graal.exe and compiled in, the zips hold no original Graal code,
graphics, sounds or levels. The client carries simple graphics of its own.

## What's new in v0.0.5

- [x] **Spin attack.** With the spin status (STATUS bit 0x40, from the server or the spin attack item), pressing S again while the swing still plays cuts it off and plays `spin` (13 ticks, then idle); S during the spin is ignored. Modelled on the live 2.05 and 2.22 runs; the 1.21 readme names laying items, but this build was not run for it. What the spin hits (a box round the player here) is not yet checked on the real client (#302).
- [x] **Laying items.** Hold S and press A to pick an item to lay; it shows over the head. A again with S held picks the next item, A alone lays it in front, and an arrow, S or D leaves without laying. Rupees, bombs, darts, a heart, the glove, a stock sword or shield and the spin can be laid, at the 2.05 costs; online a laid floor item is sent as `PLI_ITEMADD` (12). A custom sword or shield picture is not laid yet, and water in front is not told apart from land (#302).
- [x] **Its own token.** Logs in with `GSERV011`, as 1.27 did.
- [x] **Its own start dialog and forms.** 1.27's TConnectFrame, game window,
  F1 window and icon, compiled in from its exe, and its character list.
- [x] **The 1.27 start dialog.** Its language list (filled from the
  install's `language*.txt`), and One Player keeps the Nick Name row, as
  1.27 and 1.28 beta 2 do.
- [x] **Builds with Delphi 7** as well as Free Pascal.
- Everything else is as in the 1.21 rebuild, v0.0.4.2: the real start dialog
  and frame, the modes, the character list, online defaults, the game window,
  asleep at the start, F1, the default server, other players' one-byte id.

## Not yet

- [ ] The server ids and GS1 commands limited to 1.27's sets.
- [ ] The Nick Name row in One Player mode.
- [ ] The prop encodings checked against 1.27; the `nodecompressionerror=` option; server messages 35 to 38.
- [ ] Local 2 to 4 player modes and this version's options.
