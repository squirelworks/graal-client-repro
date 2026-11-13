# Graal Worlds token `G3D2204D`: INFERRED stand-in

**Evidence: no binary.** No client that sends `G3D2204D` is held. The
token is known from two places only (graal_analysis):

- gs2lib's token table names it `CLVER_WORLDS`, "Graal Worlds"
  (`protocol/v7-connector-live-20261111.md`);
- the 6.11 connector script lists it with `G3D2304D`, `G3D2404D` and
  `G3D2504D` among the legacy tokens of its old login path
  (`protocol/connector-script.md`).

Its date stamp reads 22 April with the year digit after 6.03r7's
(`G3D0311C`, November 2012), so it is taken to be a 2013 Windows build
between 6.03r7 and the connector-based 6.11. The folder is named
`worlds2013` for that guess. It is not one of the Unity "Worlds" builds
(`graal-worlds-*`), which carry no token at all.

This folder is the Windows 6.03r7 rebuild (`graal-6.03r7win-G3D0311C`),
the nearest real build before it, sending that token. It exists so a
server's `CLVER_WORLDS` entry can be tested; it is not a reproduction of a
real client. Everything below the token is 6.03r7's.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

## What differs from the 6.03r7 Windows rebuild

| | 6.03r7 Windows | This stand-in |
|---|---|---|
| Game token | `G3D0311C` (seen on the wire) | `G3D2204D` (listed only) |
| Login machine fields | `""` × 4 on main | made-up hashes of the original's shape, then the quoted Windows version |

The machine hashes are the MD5 hex of "SquirrelOS product id
SQRL7-ACORN-OAK42-NUTS1", of "SquirrelNIC MAC AC:04:2D:5E:ED:01" and of
"SquirrelBIOS C: volume serial ACE5-5EED". Nothing is read from the
player's machine.

## Units

As in 6.03r7 Windows, with the suffix `2204d`: `Protocol2204d`,
`GraalClient`, `Adventure`, `Graal2204d.dpr`, `ListServer2204d`,
`StartScreen2204d`, `Grescr2204d`, `RunMode`.

## Running it

```
GRAAL_PW=... Graal2204d --server HOST:PORT --account NAME
Graal2204d --level some.nw                  # offline
```

## Not yet, or not known

- [ ] A real client that sends `G3D2204D`, and what it is. Until one turns up, nothing about it is known beyond the token.
- [ ] Whether the production connector ever made a client send this token (graal_analysis `protocol/v7-connector-live-20261111.md`, open point 2).
- [ ] Everything still missing from the 6.03r7 Windows rebuild.
