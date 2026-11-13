# Graal 4.02.11 (`G3D28095`): INFERRED stand-in

**Evidence: no binary.** No 4.02.11 client has been found in any
collection. Its token, `G3D28095`, comes only from the public version list
(GServer-v2 `versions.txt` / gs2lib's token table; graal_analysis
`client-internals/version-token-catalogue.md`, grade L). Read as G3D + day,
month and year digit it is 28 September 2005, between 3.151 (`G3D27015`)
and 4.03r1 (`G3D11125`).

This folder is the Windows 4.20r8 rebuild (`graal-4.20r8-G3D20126`,
without its `Shell420` engine shell) sending that token. It exists so a
server's 4.02.11 entry can be tested; it is not a reproduction of a real
4.02.11. Everything below the token is 4.20r8's.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

## Why 4.20r8

The nearest real Windows 4.x builds on each side are 4.03r3 (`G3D09125`,
no folder on main yet) and 4.04r2 (`graal-4.04r2-G3D17026`). 4.04r2's
folder carries 4.04r2's own resources, which must not be reused for
another version, so the lean 4.20r8 rebuild (no extracted resources) is
the base, as for the other 4.0x stand-ins.

## What differs from the 4.20r8 rebuild

| | 4.20r8 | 4.02.11 (this folder) |
|---|---|---|
| Game token | `G3D20126` | `G3D28095` (listed only) |
| Login machine fields | `""` × 3 on main | made-up hashes of the original's shape |
| `Shell420` | built | not carried over |

The machine hashes are the MD5 hex of "SquirrelOS product id
SQRL7-ACORN-OAK42-NUTS1", of "SquirrelNIC MAC AC:04:2D:5E:ED:01" and of
"SquirrelBIOS C: volume serial ACE5-5EED". Nothing is read from the
player's machine.

## Units

As in 4.20r8, with the suffix `40211`: `Protocol40211`, `GraalClient`,
`Adventure`, `Graal40211.dpr`, `ListServer40211`, `StartScreen40211`,
`RunMode`.

## Running it

```
GRAAL_PW=... Graal40211 --server HOST:PORT --account NAME
GRAAL_PW=... Graal40211 --server HOST:14900 --account NAME --server-name Login
Graal40211 --level some.nw                  # offline
```

## Not yet, or not known

- [ ] A real 4.02.11 binary. Until one turns up, nothing about this client is known beyond its listed token.
- [ ] Whether 4.02.11 handles 107, 108 and 196 (4.20r8's 101 ids are used).
- [ ] Everything still missing from the 4.20r8 rebuild.
