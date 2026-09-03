#!/bin/bash
# Makes the signing certificates Glassine needs, without Xcode.
#
# Xcode's Accounts pane is the usual way to get these, but its UI refuses to
# launch on a macOS newer than it shipped for — while the command line tools the
# build actually uses keep working. Apple will issue a certificate from a signing
# request instead, which is all this does: generate the request here, you upload
# it in a browser, then import what comes back.
#
#   ./newcert.sh app                       signing request for the app certificate (App Store)
#   ./newcert.sh installer                 signing request for the installer certificate (App Store)
#   ./newcert.sh developerid               signing request for the Developer ID certificate (direct download)
#   ./newcert.sh app --import ~/Downloads/foo.cer     import the issued certificate
#
# The private keys live in ~/GlassineSigning (mode 700) and never leave this Mac.
# They are not in the repository and must not be: a certificate is worthless to
# anyone without the matching key, and dangerous to you with it.
set -euo pipefail

DIR="${GLASSINE_SIGNING_DIR:-$HOME/GlassineSigning}"
KIND="${1:-}"
case "$KIND" in
  app)       WANT="Apple Distribution" ;;
  installer) WANT="Mac Installer Distribution" ;;
  developerid) WANT="Developer ID Application" ;;
  *) echo "usage: ./newcert.sh app|installer|developerid [--import <file.cer>]" >&2; exit 1 ;;
esac

# Whatever the certificate is issued to, it belongs to the Apple ID that uploads
# the request; the subject is only a label.
SUBJECT="${CSR_SUBJECT:-/emailAddress=${APPLE_ID:-alex@alexlibre.com}/CN=${CSR_NAME:-Alex Libre}/C=US}"
KEY="$DIR/$KIND.key"
CSR="$DIR/$KIND.csr"

mkdir -p "$DIR"; chmod 700 "$DIR"

if [[ "${2:-}" == "--import" ]]; then
  CER="${3:-}"
  [[ -f "$CER" ]] || { echo "No certificate at '$CER'." >&2; exit 1; }
  [[ -f "$KEY" ]] || { echo "No private key at $KEY — run ./newcert.sh $KIND first." >&2; exit 1; }

  # A certificate issued from a different request will import happily and then
  # fail to sign, in a way that is tedious to diagnose. Compare the public keys.
  form=DER; openssl x509 -inform DER -in "$CER" -noout >/dev/null 2>&1 || form=PEM
  cert_pub="$(openssl x509 -inform $form -in "$CER" -noout -pubkey 2>/dev/null | openssl md5 || true)"
  key_pub="$(openssl rsa -in "$KEY" -pubout 2>/dev/null | openssl md5 || true)"
  if [[ -z "$cert_pub" || "$cert_pub" != "$key_pub" ]]; then
    echo "That certificate does not match $KEY." >&2
    echo "It was probably issued from the other .csr — check which file you uploaded." >&2
    exit 1
  fi

  security import "$KEY" -k "$HOME/Library/Keychains/login.keychain-db" \
    -T /usr/bin/codesign -T /usr/bin/productbuild >/dev/null 2>&1 || true
  security import "$CER" -k "$HOME/Library/Keychains/login.keychain-db" \
    -T /usr/bin/codesign -T /usr/bin/productbuild
  echo "▸ Imported. Matching identities now in the keychain:"
  security find-identity -v 2>/dev/null | grep -E "$WANT|3rd Party Mac Developer" || {
    echo "  (none found — the certificate imported but is not a valid identity yet)" >&2
    exit 1
  }
  exit 0
fi

if [[ ! -f "$KEY" ]]; then
  openssl genrsa -out "$KEY" 2048 2>/dev/null
  chmod 600 "$KEY"
  echo "▸ New private key: $KEY"
else
  echo "▸ Reusing the existing private key: $KEY"
fi
openssl req -new -key "$KEY" -out "$CSR" -subj "$SUBJECT" 2>/dev/null
echo "▸ Signing request: $CSR"
cat <<EOF

Next:
  1. developer.apple.com/account/resources/certificates/add
  2. Choose "$WANT", continue, and upload:
       $CSR
  3. Download the .cer, then:
       ./newcert.sh $KIND --import ~/Downloads/<the file>.cer

Upload the right .csr for each certificate — each kind has its own key, and a
mismatch only shows up later, at signing time.
EOF
command -v open >/dev/null && open 'https://developer.apple.com/account/resources/certificates/add' 2>/dev/null || true
