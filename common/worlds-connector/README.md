# Shared Worlds connector scaffold (SEIWRLD1)

One connector scaffold for **every** Graal Worlds build in this repo
(`graal-worlds-548-*` through `graal-worlds-71243-*`, and
`graal-worlds-7.0.1.7.5.0-*`). It is shared, not per build, because the
Worlds builds share one connector on the client side (below).

It mirrors the per-build 6.11 scaffold in `graal-6.11r1-mac/connector/`;
the reply container is the same.

- `worlds-connector.gs`: the connector script. Its `onCreated` sets the
  `EILLLT` header, sends the placeholder token `SEIWRLD1` with `sendRaw`,
  and calls `setEncryptionOut` with the pending name `SEI-PENDING`.
- `make-conf.sh`: signs the script into a `conf.gs` reply, byte-for-byte
  the 6.11 container: `u32be(256)`, the RSA-2048 PKCS#1 v1.5 signature
  over the bare SHA-256 digest of the payload, `u32be(N)`, the payload.
  It reads the private key from `SEI_CONNECTOR_KEY`, a path outside the
  repo; the key is never committed. The matching public modulus is the
  same project key the 6.11 scaffold names (`SeiPublicModulusHex` in
  `graal-6.1.1.3-GNP1905C/src/Connector6111.pas`). The signed
  `seiwrld1-conf.gs` is not committed here; rebuild it with the key.

## Why one shared scaffold

From the cross-build teardown of the six Windows Worlds engine images
(548, 610, 612, 613, 614, 71243), recorded in the Graal_analysis v7
notes **[bin]**:

- **No Worlds build bakes an eight-character login token.** None of the
  images stores a `G3D…`/`GNP…` style literal. The classic per-version
  token does not exist in these builds.
- **The baked connector configuration is byte-identical across the
  builds.** The scrambled connector blobs that sit next to `scriptip`,
  `scriptsslissuer` and `scripttimestamp` are the same bytes in every
  build; only the reported client version differs.
- **The connector container is the same as 6.11.** The reply is the
  `00 00 01 00` marker, a 256-byte RSA-2048 signature, a length, then an
  encrypted payload — the container the 6.11 clients use.

So on the client side there is one connector, shared by every Worlds
build, and the login token is supplied by the server's connector script
(the same mechanism as 6.11), not baked per build. One shared scaffold is
the faithful model; seven per-build copies would not be.

## Reported client versions

The Worlds builds identify to the connector only by an HTTP `User-Agent`
(`User-Agent: Graal/<version>`), not by a baked token **[bin]**:

| Builds | `User-Agent` |
| --- | --- |
| 548, 610, 612 | `Graal/6.76` |
| 613, 614, 71243 | `Graal/6.77` |

(The native plugin's VERSIONINFO is `6.114` in all of them; that is the
plugin's version, not the client version it reports.) The `User-Agent`
for `7.0.1.7.5.0` is not recorded here.

## Not yet

- `SEIWRLD1` is a placeholder. No game server accepts it until
  `seihai-gserver-v2` handles it, and the session cipher and key in
  `setEncryptionOut` are still pending.
- Whether the live token is a single value for all Worlds builds, or the
  server returns a version-keyed value from the `User-Agent`, is **not**
  confirmed. The client bakes no token and its connector config is shared,
  which is what this scaffold records; the server-side value awaits a live
  Worlds connector trace (the 6.11 desktop clients were traced; a Worlds
  trace was not completed). Until then the Worlds folders do not use this
  scaffold, exactly as their READMEs state.

> **Not affiliated.** An independent fan project. Not affiliated with,
> endorsed by, or connected to Graal Online, Cyberjoueurs, or Stéphane
> Portha ("unixmad").
