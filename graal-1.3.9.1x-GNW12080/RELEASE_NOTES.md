# Graal 1.3.9.1x (GNW12080), 0.0.1, inferred

A client that logs in with `GNW12080`, the token the server software of
2000 lists for 1.391. No copy of a build that sends it is known; this is
the 1.39 revision 1 rebuild with that token, so servers can be tested with
it. The `x` marks it as inferred.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

## What's new in v0.0.5

- [x] **Sword hits as this build judges them.** A sword tip exactly 2 tiles to the side now hits (every build from 1.21 to 2.31 includes the edge); no once-a-second limit per attacker (it arrives in 2.01); the attacker's sword power is kept raw in 6 bits, with no plus or minus 20 limit, so a negative power never heals (the limit arrives in 2.03). Read in the binaries for seihai-core #28 (#302).
- [x] **Bushes and pots drop items.** As 1.33 to 1.41 do, the client rolls the drop itself: one `Random(100)` per cut or lifted bush (a green rupee 25 in 100, a blue one 2, a heart 5, bombs 5), and a lifted pot always leaves a heart; the roll is sent to the server as `PLI_ITEMADD` (12), as the 1.39 capture shows (#302).
- [x] **Baddies drop items.** A baddy that starts dying rolls its item, as every build from 1.21 to 1.41 does: a green rupee 10 in 100, a blue one 5, a heart 15, and darts 45 from an archer or type 4 (#302).
- [x] **Swamp soldiers.** The sword reaches a swamp soldier from the moment it surfaces (counter 17), as 1.21 to 2.00 do; touching it still needs counter 22 to 36 (#302).
- [x] **Spin attack.** With the spin status (STATUS bit 0x40, from the server or the spin attack item), pressing S again while the swing still plays cuts it off and plays `spin` (13 ticks, then idle); S during the spin is ignored. Modelled on the live 2.05 and 2.22 runs; the 1.21 readme names laying items, but this build was not run for it. What the spin hits (a box round the player here) is not yet checked on the real client (#302).
- [x] **Laying items.** Hold S and press A to pick an item to lay; it shows over the head. A again with S held picks the next item, A alone lays it in front, and an arrow, S or D leaves without laying. Rupees, bombs, darts, a heart, the glove, a stock sword or shield and the spin can be laid, at the 2.05 costs; online a laid floor item is sent as `PLI_ITEMADD` (12). A custom sword or shield picture is not laid yet, and water in front is not told apart from land (#302).
- [x] **The 1.391 token, `GNW12080`**, on the 1.39 revision 1 login line.
- Everything else is as in the 1.39 revision 1 rebuild.

## Not yet

- [ ] A real `GNW12080` binary to check against, if one turns up.
- [ ] Everything still open in the 1.39 revision 1 rebuild.
