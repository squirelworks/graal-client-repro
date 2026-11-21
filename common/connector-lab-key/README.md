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

## Secret scanners

The private key here is listed as ignored for GitHub secret scanning
(`.github/secret_scanning.yml`), gitleaks (`.gitleaks.toml`) and trufflehog
(`.trufflehogignore`, passed with `--exclude-paths`), so it does not raise
alerts. Do not add an operator key to those lists.

## Project transport fixtures

`lab-server-key.pub.pem` and `lab-parse-key.pub.pem` are intentional public
RSA-2048 SPKI keys, with exponent 65537; matching `.modulus` files contain
`Modulus=` followed by 512 big-endian hex digits. The new private server and
parse keys are runtime-only and are not committed. These public fixtures do
not establish operator identity. The existing open signing fixture is unchanged.

For a fresh isolated lab, generate two runtime RSA pairs outside the checkout.
Configure the server with its private PKCS#1 PEM and the parse public SPKI PEM.
Replace the public modulus strings in the project connector script to match
those runtime pairs and re-sign the script with `make-conf.sh`. The client
receives the parse private exponent as `SEI6113_PARSE_PRIVATE_EXPONENT` (contiguous even-length hex,
big-endian, 2 through 512 digits; no prefix, separators or whitespace); it is bound to the script's `parsePrivateExponent` variable.
Never put private exponents, runtime scripts containing them or private PEMs
in Git. A missing runtime parse exponent fails before any script socket write.
