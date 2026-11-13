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

## What's new in v0.0.1

- [x] **Its own token, `GNW23090`**, on no public version list, with the
  gen-3 key byte as the real 1.40 rev 1 sends it.
- [x] **Its own forms and icon** from the 1.40 rev 1 exe, and its language
  files read from next to the program, where 1.40 keeps them.
- [x] **Builds with Delphi 7** as well as Free Pascal.
- Everything else is as in the 1.41 rev 1 rebuild, v0.0.5.

## Not yet

- [ ] The 1.40 PK tag rules, per-account passwords and the F8 server list.
- [ ] Everything still open in the 1.41 rev 1 rebuild.
