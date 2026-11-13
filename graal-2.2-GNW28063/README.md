# Graal 2.2 (`GNW28063`), inferred

**No binary of Graal 2.2 is held.** The token is the one gs2lib's version
table lists for 2.2. Squirrel asked for every listed token to have a
client (2026-11-13), so this folder is the nearest real rebuild,
`graal-2.17.1-GNW22122`, with the token and the build label changed and the link moved to generation 4.
Everything else (forms, art, Training levels, behaviour) is 2.17.1's, and
should be read as such.

What is known of 2.2 itself: gen 4, as 2.19.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").


## The link

The link is generation 4, written from graal_analysis `protocol/codec-and-framing.md` (gen 4, client type 4, server source): the login line is type 4, the key byte, `GNW28063`, account and password, alone in a u16be + zlib frame with no XOR (as 2.22 sends its login); every later frame, both ways, is u16be + a bzip2 body whose first 4 dword groups are XORed with the gen-5 LCG, one iterator per direction seeded 0x04A80B38 with the key, with no compression byte. The messages after the login, PLI_LANGUAGE and PLI_TAMPERCHECK (2.17.1's bytes) are 2.17.1's. No real gen-4 client has been captured, so all of this is inferred.

## Where it finds its files

As the 2.17.1 rebuild, under `graal-assets/2.2/` first and then 2.17.1's folders.
It carries 2.17.1's program resources but **not** its install: put a 2.x install
next to it, or a `graal-assets/` folder, or point at one with `--data`.

## Checks for 0.0.1

- Builds with Free Pascal on Windows; its tests pass with no leaks (the login, receive and fuzz tests of 2.17.1, rewritten for the gen-4 frames).
- There is no real client to compare with.

## Not yet

- [ ] A real 2.2 binary, if one turns up, to replace the inference.
- [ ] Everything still open in the 2.17.1 rebuild.
