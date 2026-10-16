#!/usr/bin/env bash
set -euo pipefail

NAME="Reframed Local Signing"
KEYCHAIN_NAME="reframed-signing"
KEYCHAIN="$HOME/Library/Keychains/$KEYCHAIN_NAME.keychain-db"
PASS="${REFRAMED_SIGNING_PASSWORD:-reframed-local}"

if security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$NAME"; then
  echo "signing identity already present: $NAME"
  exit 0
fi

WORK="$(mktemp -d)"
openssl req -x509 -newkey rsa:2048 -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
  -days 3650 -nodes -subj "/CN=$NAME/O=Reframed Fork/C=AU" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "basicConstraints=critical,CA:false"

openssl pkcs12 -export -out "$WORK/cert.p12" -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -passout "pass:$PASS" -macalg sha1 -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES

security create-keychain -p "$PASS" "$KEYCHAIN_NAME.keychain" 2>/dev/null || true
security set-keychain-settings "$KEYCHAIN_NAME.keychain"
security unlock-keychain -p "$PASS" "$KEYCHAIN_NAME.keychain"
security import "$WORK/cert.p12" -k "$KEYCHAIN_NAME.keychain" -P "$PASS" \
  -T /usr/bin/codesign -A
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASS" \
  "$KEYCHAIN_NAME.keychain" >/dev/null
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

security find-identity -v -p codesigning "$KEYCHAIN"
echo "created stable signing identity: $NAME"
