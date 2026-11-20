# Open lab connector key (not a secret)

**This key is public on purpose. It authenticates nothing.**

The 6.11-style clients run a connector script only when the `conf.gs`
reply carries an RSA-2048 signature (PKCS #1 v1.5 over the bare SHA-256
digest) that verifies against a public key built into the client. Stock
Graal uses that to make sure only the operator's script runs.

This project is open source, so a hidden project key would protect
nothing and would leave the signed scripts impossible to rebuild. Instead:

- `lab-signing-key.pem` (private), `lab-signing-key.pub.pem` (public) and
  `lab-signing-key.modulus` (the modulus in hex) are committed here.
- The rebuilt clients (`Connector6113`, `Connector6111`) trust this key by
  default (`SeiPublicModulusHex`). A signature under it only shows that
  the script arrived unchanged. Anyone can sign with it.
- Every `make-conf.sh` signs with it when `SEI_CONNECTOR_KEY` is unset, so
  the shipped `sei00001-conf.gs` files rebuild with no secrets.
- A server operator who wants clients to run only their own script makes
  their own key pair, keeps the private half to themselves, signs with
  `SEI_CONNECTOR_KEY=/their/private.pem sh make-conf.sh ...`, and starts
  the clients with `--connector-key FILE`. FILE holds the modulus as
  `openssl rsa -pubin -in pub.pem -noout -modulus` prints it.

Make an operator key with:

```
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out operator.pem
openssl rsa -in operator.pem -noout -modulus > operator.modulus
```

Never reuse this lab key for anything that needs to be secret.
