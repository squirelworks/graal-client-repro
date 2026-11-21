# Project connector files

- `sei00001-connector.gs` is the signed project transport script. It sets
  EILLLT, sends raw `SEI00001`, creates a fresh OS-random 16-byte key,
  RSA-wraps it to the server public modulus, sends one whole clear nested
  key frame and enables outgoing RC4. The server's separate key reply
  enables incoming RC4. See [CIPHER.md](CIPHER.md) for the exact contract.
- `sei00001-conf.gs` contains u32be(256), the RSA-2048 signature over the
  bare SHA-256 payload digest, u32be(N), then the deliberately clear script.
  The signature is checked before any script is run.
- `make-conf.sh` rebuilds the reply. By default it uses the existing open
  signing fixture in `common/connector-lab-key`, public on purpose and not
  an operator identity. Operators can sign with their own runtime key and
  start the client with `--connector-key FILE`.

The parse private exponent is supplied at runtime through
`SEI6113_PARSE_PRIVATE_EXPONENT`, bound to `parsePrivateExponent` in the
script. It must be contiguous, even-length big-endian hexadecimal (2 through
512 digits), without a prefix, whitespace, colons or PEM framing. A missing
value fails before script socket writes; the TCP connection may already exist.
New private server/parse PEMs and exponents stay outside Git. Only their public
SPKI/modulus fixtures are committed. Fresh runtime pairs require matching both
public modulus strings in the runtime script, then re-signing it; see
`common/connector-lab-key/README.md`.

The shipped script stays byte-equal to `SeiConnectorScript`, and tests verify
its signed container. This implements project key exchange and a bounded
decrypted transport buffer only. Account/game admission and gameplay dispatch
remain open. Raw project selection is separate from classic-framed SEI00001
secure login and the original raw GNP1905C stop path; failure never downgrades
between those routes. No stock-client or joint VM acceptance is implied.
