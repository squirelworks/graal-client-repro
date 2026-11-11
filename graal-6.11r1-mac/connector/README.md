# Connector files (SEI00001 scaffold)

- `sei00001-connector.gs`: this project's connector script. It sets the
  `EILLLT` header, sends the placeholder token `SEI00001` with `sendRaw`,
  and calls `setEncryptionOut` with the pending name `SEI-PENDING`.
- `sei00001-conf.gs`: that script signed as a `conf.gs` reply:
  u32be(256), the RSA-2048 signature over the bare SHA-256 digest of the
  payload, u32be(N), the payload. The payload cipher is pending, so the
  payload is the script text.
- `make-conf.sh`: rebuilds the reply. It reads the private key from
  `SEI_CONNECTOR_KEY`, a path outside the repo. The private key is never
  committed. The matching public modulus is `SeiPublicModulusHex` in
  `src/Connector6111.pas`.

The script text must stay byte-equal to `SeiConnectorScript`; the tests
check it. `SEI00001` is not yet usable: no game server accepts it until
seihai-gserver-v2 handles it.
