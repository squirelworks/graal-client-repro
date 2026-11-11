# Graal 6.11r1 Mac (`Graal/6.111`)

The first rebuild of a client that acts like Mac OS X 6.11r1. Original
Pascal. It shares the 6.1.1.3 folder's framer and connector units.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

## What's new in v0.0.5

- Connector login, the only login 6.11 has. It does `GET /conf.gs` with
  `User-Agent: Graal/6.111` and retries twice on a second connector, then
  shows "Couldn't connect to the server". It checks the RSA-2048
  signature with the project's own key before anything runs, then runs
  the connector script: `setProtocol("EILLLT")`, `sendRaw`,
  `setEncryptionOut`.
- The project script sends the placeholder token `SEI00001`. **Not yet
  usable**: the client stops after the hello until seihai-gserver-v2
  handles it.
- `--lab` continues after the hello on a labeled lab-only fixture: one
  other entity, its properties, and a movement round trip.
- A window (when `--window` can open one), a software camera, a local
  player, and lab-only collision on `levels/lab-yard.lvl`.

## Not yet

- [ ] `SEI00001` on the game server (seihai-gserver-v2).
- [ ] The `conf.gs` payload cipher and the session cipher.
- [ ] The HTTPS step, the `p=` blob, `con.png` and `con.gs`.
- [ ] The rest of the connector script surface and GS2.
- [ ] OpenGL and the real window size.
- [ ] macOS was not run here.
