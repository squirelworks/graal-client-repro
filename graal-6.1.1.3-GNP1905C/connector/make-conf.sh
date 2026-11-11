#!/bin/sh
# Sign a connector script into a conf.gs reply for the project key.
#   SEI_CONNECTOR_KEY=/path/outside/the/repo/private.pem \
#     sh make-conf.sh sei00001-connector.gs sei00001-conf.gs
# The private key never goes in the repo. The reply is:
#   u32be(256) signature u32be(N) payload
# where signature is RSA-2048 PKCS #1 v1.5 type 1 over the bare SHA-256
# digest of payload (no DigestInfo). The payload cipher is pending, so the
# payload is the script text as is.
set -eu
: "${SEI_CONNECTOR_KEY:?set SEI_CONNECTOR_KEY to the private key path}"
IN=$1
OUT=$2
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
openssl dgst -sha256 -binary "$IN" > "$TMP/digest"
openssl pkeyutl -sign -inkey "$SEI_CONNECTOR_KEY" -pkeyopt rsa_padding_mode:pkcs1 \
  -in "$TMP/digest" -out "$TMP/sig"
u32be() { printf "$(printf '\\%03o\\%03o\\%03o\\%03o' \
  $(( ($1 >> 24) & 255 )) $(( ($1 >> 16) & 255 )) $(( ($1 >> 8) & 255 )) $(( $1 & 255 )))"; }
{ u32be "$(wc -c < "$TMP/sig")"; cat "$TMP/sig"; u32be "$(wc -c < "$IN")"; cat "$IN"; } > "$OUT"
echo "wrote $OUT ($(wc -c < "$OUT") bytes)"
