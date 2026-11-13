# Graal 1.38 revision 1 (GNW02070), 0.0.1

A first rebuild of the Graal 1.38 rev 1 client (July 2000) in Delphi
(Object Pascal), for Linux and Windows, made from the 1.38 rebuild. It logs
in the way 1.38 rev 1 did and plays a level offline. It is early and many
parts still behave like a later Graal: see "Not yet".

**Login token: tested against the real client.** The original was run in
the lab (2026-11-13) and `GNW02070` was seen in its login on the wire; this
rebuild sends the same login bytes.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

## What's new in v0.0.5

- [x] **Its own token, `GNW02070`** (gs2lib's 1.381), from the real exe.
- [x] **Its own forms and icon**, compiled in from the 1.38 rev 1 exe.
- [x] **Builds with Delphi 7** as well as Free Pascal.
- Everything else is as in the 1.38 rebuild.

## Not yet

- [ ] The "Don't connect levels" option and the web browser control.
- [ ] Everything still open in the 1.38 rebuild.
