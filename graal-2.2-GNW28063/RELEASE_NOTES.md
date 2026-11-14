# Graal 2.2 (GNW28063), inferred, INVENTED link

A client that logs in with `GNW28063`, the token gs2lib lists for Graal 2.2. No
binary of 2.2 is known; this is the 2.17.1 rebuild with that token on the generation-4 link 2.19 to 2.21 used. It is
for testing servers with the 2.2 login.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

**Invented link.** The generation-4 link this client uses is made up to
work, not observed: no 2.19 to 2.21 client or type-4 login has ever been
captured. seihai-gserver serves the same invention.

## What's new in v0.0.5

- [x] **Spin attack.** With the spin status (STATUS bit 0x40, from the server or the spin attack item), pressing S again while the swing still plays cuts it off and plays `spin` (13 ticks, then idle); S during the spin is ignored. Modelled on the live 2.05 and 2.22 runs. What the spin hits (a box round the player here) is not yet checked on the real client (#302).
- [x] **Laying items.** Hold S and press A to pick an item to lay; it shows over the head. A again with S held picks the next item, A alone lays it in front, and an arrow, S or D leaves without laying. Rupees, bombs, darts, a heart, the glove, a stock sword or shield and the spin can be laid, at the 2.05 costs; online a laid floor item is sent as `PLI_ITEMADD` (12). A custom sword or shield picture is not laid yet, and water in front is not told apart from land (#302).
- [x] **The 2.2 token, `GNW28063`**, with the generation-4 link (type 4, bzip2 frames, partial XOR).
- Everything else is as in the 2.17.1 rebuild.

## Not yet

- [ ] A real 2.2 binary to check against.
