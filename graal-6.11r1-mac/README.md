# Graal 6.11r1 Mac (`Graal/6.111`)

A client that acts like the Mac OS X 6.11r1 build (`Graal v6.11r1[Mac OS
X]`, CFBundleVersion 6.111). There is no other 6.111 build to model on, so
this folder follows the Mac 6.11 readings in Graal_analysis and reuses the
6.1.1.3 folder's framer where the notes say the two match.

The folder name ends in `mac`, not a token: 6.11 stores no version token.
The connector script the server sends decides the first eight bytes.

> **Not affiliated.** graal-delphi is an independent fan project. It is not
> affiliated with, endorsed by, or connected to GraalOnline or
> graalonline.com, Cyberjoueurs, or Stéphane Portha ("unixmad").

## What makes it 6.111

| 6.11 behaviour | Note | This folder |
|---|---|---|
| No compiled-in token and no clear-hello path. Login always goes through a connector | `protocol/v6x-clients.md` "6.11 Mac: the connector" | `--server` needs `--connector`. `ConnectorOnly = True` |
| `GET /conf.gs` over plain HTTP/1.0 with `User-Agent: Graal/6.111` and `Connection: Keep-Alive` | same, "The connector request in a lab run" | Same request line and headers, to loopback, with no `Host` name and no `p=` blob |
| One try plus up to two retries, the retries on a second connector (`con` then `con2`). After three failures: "Couldn't connect to the server" | same | `--connector A,B`: try A, then B twice, then that warning |
| The reply is a signature (RSA-2048 over the bare SHA-256 digest) and a payload. The signature is checked before anything runs | `protocol/v6-login-token-explained.md` | `Rsa6111`, `Sha6111`, checked against **this project's own public key** |
| The connector script calls `setProtocol("EILLLT")`, `sendRaw(token)`, `setEncryptionOut(...)`, with no wait between them | same | `Connector6111.RunConnectorSteps` |
| The generation-5 framer is the default until `setprotocol`. Seed and multiplier shared with 6.00 to 6.03 | `protocol/v6x-clients.md` "Cipher and framing", "What the script controls" | `Frame6111`, copied from the 6.1.1.3 folder. The seed is the one the notes give |
| `tclient_set*` property setters | same | `Props6111` stores one string per setter. No 6.11 id table was read, so none is copied |

## The token: SEI00001, not yet usable

This project's connector script (`connector/sei00001-connector.gs`, signed
into `connector/sei00001-conf.gs`) sends the placeholder **`SEI00001`**.
`SeiTokenUsable = False`. No game server accepts it until the matching
handling lands in seihai-gserver-v2. Until then a login stops after the
hello (`stopped after SEI00001 hello`, summary `"end":"sei-pending"`).
`--lab` continues past the hello on the lab fixture instead, so the yard
can be walked.

The payload cipher and the session cipher are not chosen. The payload is
read as clear, and `setEncryptionOut` is called with the pending name
`SEI-PENDING`, which selects no cipher.

## Layers

| Layer | What it is |
|---|---|
| verified-from-evidence | The connector order (fetch, verify, run), the retry count and the second connector, the request line and headers, the signature shape, the `EILLLT` template and the call order, the generation-5 seed, `setencryptionout` names |
| provisional adapter | Two loopback ports stand in for the two connector hosts. The repo window and software surface instead of OpenGL. zlib and bzip2 through the repo units |
| lab-only fixture | `levels/lab-yard.lvl`, the colours, the 4-pixel step, collision, the camera, and every byte after `SEI00001` when `--lab` is set |

## Running it

From the repo root, after `scripts/build.sh graal-6.11r1-mac`:

```
build/graal-6.11r1-mac/Graal6111 --connector-serve 14901 \
  --conf graal-6.11r1-mac/connector/sei00001-conf.gs --seconds 20
build/graal-6.11r1-mac/Graal6111 --lab-serve 14900 --seconds 20
build/graal-6.11r1-mac/Graal6111 --server 127.0.0.1:14900 \
  --connector 127.0.0.1:14901 --lab \
  --level graal-6.11r1-mac/levels/lab-yard.lvl --window --keys "right*6"
```

`--lab-serve --quiet` records the `SEI00001` hello and sends nothing, as a
real server must until it handles the token. `--window` opens the repo's
window titled `Graal v6.11r1[Mac OS X]` at the lab view size.
`--password-env` is accepted and never sent or logged. `--server` and
`--connector` must be `127.0.0.1`.

`scripts/loopback.sh` runs the connector login against a local
seihai-gserver and expects the stop after `SEI00001`. It does not count a
gserver login.

## Not yet

- [x] Connector login: `conf.gs`, retries, project-key signature check, then the connector script with `EILLLT` and `SEI00001`.
- [ ] TODO(seihai-gserver-v2): `SEI00001` on the game server. Until then the login stops after the hello.
- [ ] The project's `conf.gs` payload cipher and the session cipher.
- [ ] The HTTPS step before plain HTTP (TLS 1.2, compiled-in certificate bundle). Not needed by this project's connector.
- [ ] The `p=` client description. Not needed by this project's connector.
- [ ] `con.png` and `con.gs`, which the real client asks for before `conf.gs`.
- [ ] The connector script as a GS2 object (`StartScript_Connector`, `scriptip`, the SSL fields, `StartScript_Fail`) and the other script methods (`senddata`, `setoutdatahandlers`, `setindatahandlers`, `getpassword`).
- [ ] 6.11 property id tables, GS2, the OpenGL playfield, the real window size.
- [x] Side-by-side against the real 6.11r1 client (below).
- [ ] The real window: title "Graal", app and Window menus, 1024x675 from the saved config, the start-up "Select File" dialog, an app bundle with the Graal icon.

## Polishing run against the real 6.11r1 (2026-11-12)

Real 6.11r1 (x86_64) and this folder side by side on the lab macOS 15
(Sequoia) VM, offline on a restricted network, one after the other, both
pointed at a local connector logger. The repro was built natively in the VM
(FPC 3.2.2, x86_64); `Test6111` passes 127 of 127.

| Area | Real 6.11r1 | This folder | Severity |
|---|---|---|---|
| Request headers | `User-Agent: Graal/6.111`, `Connection: Keep-Alive` | Same headers, same order | match |
| First connector step | TLS on 443 first, then plain HTTP | Plain HTTP only (HTTPS step is a listed TODO) | medium |
| `conf.gs` request | `GET /conf.gs?p=… HTTP/1.0` | `GET /conf.gs HTTP/1.0`, no `p=` (listed TODO) | low |
| Retries | 1 HTTPS + 1 HTTP on `con` + 1 HTTP on `con2`, about 0.25 s in all, none more in 90 s | 3 plain-HTTP tries: A, then B twice, then "Couldn't connect to the server" | medium |
| `--window` on macOS | n/a | Crashed at AppKit start (`EInvalidOp` in `_NSGetCGFloatAppConfig`); fixed here, see below | high, fixed |
| In-game | Stops at `conf.gs`: the operator signs the reply, so no real in-game frame exists in the lab | Lab login (connector, signature, `EILLLT`, `SEI00001`, lab yard, 6 moves) runs headless | n/a |

The retry pattern was the same with a desktop session: no later retry, and
the real client draws no failure text.

Screenshots, both clients in the same desktop session at 1280x800:

| Area | Real 6.11r1 | This folder | Severity |
|---|---|---|---|
| Window title and menus | "Graal"; app menu "Graal" plus a Window menu | "Graal v6.11r1[Mac OS X]"; app menu "Graal6111"; no Window menu | high |
| Window size and place | 1024x675 at 50,25 (saved config) | 240x180 lab view, centred | high |
| Start-up dialog | A "Select File" dialog over the main window (as real 6.03r7 on Linux) | None | high |
| Playfield offline | Plain light grey; log stops at "Initialized OpenGL"; no in-game frame without the operator's connector | Lab yard; 6 Right + 4 Down moved 10 steps with the camera following | n/a |
| Dock icon | Graal icon | Generic executable (bare binary, no `.app`) | low |
| F1 | Nothing | Nothing | match |
| Quit | Clean, no crash report | Clean, no crash report | match |

Fix from this run: FPC unmasks the invalid-operation, divide-by-zero and
overflow exceptions, and AppKit's start-up computes with NaNs, so every Cocoa
window crashed. `common/GWindowCocoa.inc` now masks all floating-point
exceptions before AppKit starts. Checked on the VM, also in a desktop session: `--window` shows the
window, walks the lab yard and exits cleanly, and `graal-2.22-GNW03014`
still builds with the shared unit.

## Provenance

Original Pascal. Built from the 6.1.1.3 folder's units (renamed) and
the Graal_analysis notes named above, read but not copied. SHA-256 and
the RSA check are written from FIPS 180-4 and RFC 8017. The connector
public key is this project's own. No operator key, connector host, `p=`
value or captured reply is in the repo. The signing key is kept outside
the repo (`connector/README.md`).
