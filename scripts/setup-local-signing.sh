#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/signing-common.sh"

IDENTITY_NAME="${CUEPROMPT_LOCAL_SIGNING_NAME}"
KEYCHAIN_PATH="${HOME}/Library/Keychains/login.keychain-db"

existing_line="$(cueprompt_identity_line_for_pattern "$IDENTITY_NAME")"
if [ -n "$existing_line" ]; then
  existing_hash="$(cueprompt_identity_hash_from_line "$existing_line")"
  echo "✅ Local signing identity already exists: $IDENTITY_NAME ($existing_hash)"
  exit 0
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "❌ openssl is required to create a local signing identity"
  exit 1
fi

temp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$temp_dir"
}
trap cleanup EXIT

openssl_config="$temp_dir/cueprompt-local-signing.cnf"
certificate_path="$temp_dir/cueprompt-local-signing.crt"
private_key_path="$temp_dir/cueprompt-local-signing.key"
pkcs12_path="$temp_dir/cueprompt-local-signing.p12"
pkcs12_password="$(uuidgen)"

cat >"$openssl_config" <<EOF
[ req ]
distinguished_name = dn
x509_extensions = v3_req
prompt = no

[ dn ]
CN = ${IDENTITY_NAME}

[ v3_req ]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
EOF

echo "🔐 Creating local CuePrompt code-signing identity..."
openssl req \
  -newkey rsa:2048 \
  -x509 \
  -nodes \
  -days 3650 \
  -config "$openssl_config" \
  -keyout "$private_key_path" \
  -out "$certificate_path" >/dev/null 2>&1

openssl pkcs12 \
  -export \
  -legacy \
  -inkey "$private_key_path" \
  -in "$certificate_path" \
  -out "$pkcs12_path" \
  -passout "pass:$pkcs12_password" >/dev/null 2>&1

security import "$pkcs12_path" \
  -k "$KEYCHAIN_PATH" \
  -P "$pkcs12_password" \
  -T /usr/bin/codesign \
  -T /usr/bin/security >/dev/null

security add-trusted-cert \
  -r trustRoot \
  -k "$KEYCHAIN_PATH" \
  "$certificate_path" >/dev/null

created_line="$(cueprompt_identity_line_for_pattern "$IDENTITY_NAME")"
if [ -z "$created_line" ]; then
  echo "❌ Created certificate, but macOS did not expose it as a valid code-signing identity"
  echo "   Open Keychain Access and confirm '${IDENTITY_NAME}' is trusted in your login keychain."
  exit 1
fi

created_hash="$(cueprompt_identity_hash_from_line "$created_line")"
echo "✅ Created local signing identity: $IDENTITY_NAME ($created_hash)"
echo "💡 Reinstall CuePrompt with 'make install', then re-grant Microphone permission one last time if macOS already reset it."
