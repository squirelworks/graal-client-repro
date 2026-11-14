# Graal 1.40 rev 1 (GNW23090)

A rebuild of the classic Graal 1.40 rev 1 client (September 2000) in Delphi
(Object Pascal), made from the 1.41 rev 1 rebuild. Like the original it is a
windowed program: it opens on a start window with the language, the game
mode, the character, the nick name and Start. This is an early, hit-or-miss
first release.

**Login token: tested against the real client.** The original was run in
the lab (2026-11-13) and `GNW23090` was seen in its login on the wire, with
the gen-3 key byte; this rebuild sends the same login.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

Apart from the start dialog and the icon, which are taken from the real
Graal.exe and compiled in, these zips hold no original Graal code, graphics,
sounds or levels. Put it at the top of a 1.40 install you own and the
install's tiles, heads, bodies and levels take their place.

## What's new in v0.0.5

- [x] **Sword hits as this build judges them.** A sword tip exactly 2 tiles to the side now hits (every build from 1.21 to 2.31 includes the edge); no once-a-second limit per attacker (it arrives in 2.01); the attacker's sword power is kept raw in 6 bits, with no plus or minus 20 limit, so a negative power never heals (the limit arrives in 2.03). Read in the binaries for seihai-core #28 (#302).
- [x] **Bushes and pots drop items.** As 1.33 to 1.41 do, the client rolls the drop itself: one `Random(100)` per cut or lifted bush (a green rupee 25 in 100, a blue one 2, a heart 5, bombs 5), and a lifted pot always leaves a heart; the roll is sent to the server as `PLI_ITEMADD` (12), as the 1.39 capture shows (#302).
- [x] **Baddies drop items.** A baddy that starts dying rolls its item, as every build from 1.21 to 1.41 does: a green rupee 10 in 100, a blue one 5, a heart 15, and darts 45 from an archer or type 4 (#302).
- [x] **Swamp soldiers.** The sword reaches a swamp soldier from the moment it surfaces (counter 17), as 1.21 to 2.00 do; touching it still needs counter 22 to 36 (#302).
- [x] **Spin attack.** With the spin status (STATUS bit 0x40, from the server or the spin attack item), pressing S again while the swing still plays cuts it off and plays `spin` (13 ticks, then idle); S during the spin is ignored. Modelled on the live 2.05 and 2.22 runs; the 1.21 readme names laying items, but this build was not run for it. What the spin hits (a box round the player here) is not yet checked on the real client (#302).
- [x] **Laying items.** Hold S and press A to pick an item to lay; it shows over the head. A again with S held picks the next item, A alone lays it in front, and an arrow, S or D leaves without laying. Rupees, bombs, darts, a heart, the glove, a stock sword or shield and the spin can be laid, at the 2.05 costs; online a laid floor item is sent as `PLI_ITEMADD` (12). A custom sword or shield picture is not laid yet, and water in front is not told apart from land (#302).
- [x] **Its own token, `GNW23090`**, on no public version list, with the
  gen-3 key byte as the real 1.40 rev 1 sends it.
- [x] **Its own forms and icon** from the 1.40 rev 1 exe, and its language
  files read from next to the program, where 1.40 keeps them.
- [x] **Builds with Delphi 7** as well as Free Pascal.
- Everything else is as in the 1.41 rev 1 rebuild, v0.0.5.

## Not yet

- [ ] The 1.40 PK tag rules, per-account passwords and the F8 server list.
- [ ] Everything still open in the 1.41 rev 1 rebuild.
