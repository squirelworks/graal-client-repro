# The project connector's ciphers: decision (2026-11-20)

The project's own connector (`SEI00001`, and `SEIWRLD1` for the Worlds
builds) left two choices open: how the signed `conf.gs` payload is
encrypted, and which session cipher `setEncryptionOut` selects. This note
records the choice and why. It applies to the 6.1.1.3, 6.11r1 Mac and
shared Worlds scaffolds. The 6.1.1.3 client has the cipher as library
code (see "Status" below); the signed scripts still say `SEI-PENDING`.

## Decision

1. **Session cipher: RC4 with a fresh 16-byte key per direction per
   session, exchanged in `0xfc` packets, the way the stock 6.11 clients
   do it.**
   - Client to server: the script makes a key with `generate16ByteKey()`,
     wraps it with `rsa_encrypt` to the project server's RSA-2048 public
     key (carried in the script), sends it in an inner `0xfc` inside a
     clear `0xfd`, then calls `setEncryptionOut("RC4", key, "")`.
   - Server to client: the server makes its own 16-byte key and sends it
     in one clear `0xfd` wrapping a `0xfc`: cipher type 1 (RC4), the
     length-prefixed key and an empty IV, RSA-wrapped (PKCS #1 v1.5
     type 2) to the parse key the script hands the client with
     `setEncryptionParseKey`.
   - Plain RC4, no bytes dropped, headers encrypted, as the stock
     stream is.
2. **`conf.gs` payload: clear.** The reply keeps the stock container
   (`u32be(256)`, the RSA-2048 signature over the bare SHA-256 digest,
   `u32be(N)`, the payload), and the payload is the script text with no
   encryption layer. The signature is checked first, as now.

## Why

- **The session cipher matches what is known on the wire.** The stock
  6.11 handshake is read from captures and two offline lab runs
  (Graal_analysis `protocol/v611-outgoing-cipher.md`,
  `protocol/connector-script.md` §4c). In run B an unmodified Mac 6.111
  took a server `0xfc` with an RC4 key wrapped to its parse key and then
  read the server's stream. A server that serves its own connector
  script holds both key pairs, so it can do the same in both directions.
  So RC4 needs no invented mechanism: the same packets, the same cut at
  the end of the clear prefix, the same byte-granular stream, and a
  stock-compatible framing for the day a lab key swap lets a stock
  client run our script.
- **AES was the other option** (the `0xfc` type byte allows 2, and
  `setEncryptionOut` takes an IV for it). It is the stronger cipher, but
  no stock session was seen using it. It pads to 16-byte blocks, which
  the 6.113 capture's 7-byte writes rule out for the stock path, and it
  would add an IV path no lab has run. The type byte keeps AES open for a
  server that wants it later.
- **No session cipher** (staying clear after the hello) would be the
  least work. But it would leave the server's `0xfc` path unexercised,
  and the rebuilt 6.1x clients would then not match the stock wire after
  offset 287.
- **The payload stays clear because a key would not be secret.** Every
  rebuild is open source, so a payload key compiled into our clients
  would be public, and encrypting under it would hide nothing. The
  signature is what protects the script from tampering, and it is
  already checked before the script runs. The stock payload key is not
  recovered and is not wanted here.
- **RC4's weaknesses** (biased early keystream, no integrity) are
  accepted for fidelity. The game protocol never had integrity
  protection. A server that needs real confidentiality should run the
  link inside TLS or a VPN, not change the client's cipher.

## What it takes to land

- The client scaffolds: `generate16ByteKey`, `rsa_encrypt`
  (PKCS #1 v1.5 type 2) to the project server key, the `0xfc`/`0xfd`
  send, RC4 out, and an incoming `0xfc` handler that unwraps with the
  parse key and re-keys RC4 in.
- seihai-gserver-v2 (and later the Rust gserver): accept `SEI00001`,
  read the client's `0xfc` with the project private key, and send their
  own `0xfc`.
- The project key pairs (signing, server, parse) stay outside the repo,
  as the signing key already does (`SEI_CONNECTOR_KEY`).

## Status (2026-11-20)

- Built in the 6.1.1.3 client, with tests: `Rc46113` (RC4),
  `Frame6113.SetEncryptionOut("RC4", key)` encrypting every later byte,
  `SetEncryptionIn` and `DecryptIn` for the server's key, and
  `RsaWrapType2` / `RsaUnwrapType2` in `Rsa6113` for the key blocks, and
  `Cipher6113` for the `0xfd`/`0xfc` key frame and the server's key
  plaintext. A test runs the server's side end to end: wrap, frame, read,
  unwrap, re-key, decrypt.
- Not done: a project script that sends the key frame, re-signed with
  `SEI_CONNECTOR_KEY` (only the key holder can do that); calling the
  key-frame reader from the socket loop; the server side; the 6.11r1 Mac and
  Worlds scaffolds.
