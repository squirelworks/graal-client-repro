# Graal 2.16 (`GNW12102`), inferred

**No binary of Graal 2.16 is held.** The token is the one gs2lib's version
table lists for 2.16. Squirrel asked for every listed token to have a
client (2026-11-13), so this folder is the nearest real rebuild,
`graal-2.17.1-GNW22122`, with the token and the build label changed.
Everything else (forms, art, Training levels, behaviour) is 2.17.1's, and
should be read as such.

What is known of 2.16 itself: player props 46 to 74 (as 2.17); no PLI_TAMPERCHECK, which came with 2.17.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").


## The link

The link is 2.17.1's: generation 3, the login line type 0, the key byte, `GNW12102`, account and password, then PLI_LANGUAGE.

## Where it finds its files

As the 2.17.1 rebuild, under `graal-assets/2.16/` first and then 2.17.1's folders.
It carries 2.17.1's program resources but **not** its install: put a 2.x install
next to it, or a `graal-assets/` folder, or point at one with `--data`.

## Checks for 0.0.1

- Builds with Free Pascal on Windows; its tests pass with no leaks.
- There is no real client to compare with.

## Not yet

- [ ] A real 2.16 binary, if one turns up, to replace the inference.
- [ ] Everything still open in the 2.17.1 rebuild.
