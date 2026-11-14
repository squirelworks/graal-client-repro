# Graal 1.39 revision 1 (GNW07080), 0.0.1

A first rebuild of the Graal 1.39 rev 1 client (August 2000, FileVersion
1.3.9.1) in Delphi (Object Pascal), for Linux and Windows, made from the
1.39 rebuild. It logs in the way 1.39 rev 1 did and plays a level offline.
It is early and many parts still behave like a later Graal: see "Not yet".

**Login token: tested against the real client.** The original was run in
the lab (2026-11-13) and `GNW07080` was seen in its login on the wire, the
same token as 1.39; this rebuild sends the same login bytes.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

Apart from the start dialog, the forms and the icon, which are taken from
the real Graal.exe and compiled in, the zips hold no original Graal code,
graphics, sounds or levels. The client carries simple graphics of its own.

## What's new in v0.0.5

- [x] **Spin attack.** With the spin status (STATUS bit 0x40, from the server or the spin attack item), pressing S again while the swing still plays cuts it off and plays `spin` (13 ticks, then idle); S during the spin is ignored. Modelled on the live 2.05 and 2.22 runs; the 1.21 readme names laying items, but this build was not run for it. What the spin hits (a box round the player here) is not yet checked on the real client (#302).
- [x] **Laying items.** Hold S and press A to pick an item to lay; it shows over the head. A again with S held picks the next item, A alone lays it in front, and an arrow, S or D leaves without laying. Rupees, bombs, darts, a heart, the glove, a stock sword or shield and the spin can be laid, at the 2.05 costs; online a laid floor item is sent as `PLI_ITEMADD` (12). A custom sword or shield picture is not laid yet, and water in front is not told apart from land (#302).
- [x] **Its own forms and icon**, compiled in from the 1.39 rev 1 exe, and
  its install's character list.
- [x] **Builds with Delphi 7** as well as Free Pascal.
- Everything else is as in the 1.39 rebuild, v0.0.4.2.

## Not yet

- [ ] The profile window with kills, deaths and online time; the blocked
  `<applet>` tags in PMs.
- [ ] The server ids and GS1 commands limited to this version's sets.
- [ ] Local 2 to 4 player modes and this version's options.
