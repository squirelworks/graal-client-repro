# Graal 2.14 (GNW30042), 0.0.1, inferred

A client that logs in with `GNW30042`, the token gs2lib lists for Graal 2.14. No
binary of 2.14 is known; this is the 2.1.0.0 rebuild with that token. It is
for testing servers with the 2.14 login.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

## What's new in v0.0.5

- [x] **Spin attack.** With the spin status (STATUS bit 0x40, from the server or the spin attack item), pressing S again while the swing still plays cuts it off and plays `spin` (13 ticks, then idle); S during the spin is ignored. Modelled on the live 2.05 and 2.22 runs. What the spin hits (a box round the player here) is not yet checked on the real client (#302).
- [x] **Laying items.** Hold S and press A to pick an item to lay; it shows over the head. A again with S held picks the next item, A alone lays it in front, and an arrow, S or D leaves without laying. Rupees, bombs, darts, a heart, the glove, a stock sword or shield and the spin can be laid, at the 2.05 costs; online a laid floor item is sent as `PLI_ITEMADD` (12). A custom sword or shield picture is not laid yet, and water in front is not told apart from land (#302).
- [x] **The 2.14 token, `GNW30042`**.
- Everything else is as in the 2.1.0.0 rebuild.

## Not yet

- [ ] A real 2.14 binary to check against.
