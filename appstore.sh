#!/bin/bash
# Builds and signs the Mac App Store flavor of Glassine as an installer package
# ready for Transporter (or TestFlight through it).
#
#   ./appstore.sh 0.2.0            bump version, build, sign, package → dist/Glassine-0.2.0-AppStore.pkg
#   ./appstore.sh 0.2.0 --dry-run  same, without the version commit (for a trial run)
#
# One-time setup (see RELEASING.md, "The App Store"):
#   1. developer.apple.com → Identifiers → com.alexlibre.glassine → enable iCloud with the
#      container iCloud.com.alexlibre.glassine.
#   2. Certificates: ./newcert.sh app  and  ./newcert.sh installer, which make the
#      signing requests; upload each at developer.apple.com and import the result.
#      (Xcode's Accounts pane does the same thing, when Xcode will launch.)
#   3. developer.apple.com → Profiles → + → "Mac App Store Connect" for the App ID;
#      download it and save it as Resources/Glassine-AppStore.provisionprofile
#      (git-ignored), or point PROVISIONING_PROFILE at it.
#   4. App Store → Transporter (free) for the upload.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:-}"
DRY_RUN=0
[[ "${2:-}" == "--dry-run" ]] && DRY_RUN=1
if [[ -z "$VERSION" || ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "usage: ./appstore.sh X.Y.Z [--dry-run]" >&2
  exit 1
fi

APP_NAME="Glassine"
BUNDLE_ID="com.alexlibre.glassine"
CONTAINER_ID="iCloud.com.alexlibre.glassine"
PLIST="Resources/Info.plist"
PROFILE="${PROVISIONING_PROFILE:-Resources/Glassine-AppStore.provisionprofile}"
DIST="dist"
APP="build/$APP_NAME.app"
PKG="$DIST/$APP_NAME-$VERSION-AppStore.pkg"

# --- Preflight --------------------------------------------------------------------------
# Each lookup ends in `|| true`: nothing found is an answer, not a failure, and
# the checks below turn it into a message worth reading.
#
# Signing uses the certificate's fingerprint (the hex before the name), not the
# name: two certificates with the same name — easy to end up with — make the
# name ambiguous, and codesign refuses to guess. The name is kept for display
# and for reading the Team ID off the certificate.
identity_line() {
  # $1: a pattern like "Apple Distribution|3rd Party Mac Developer Application"; $2: policy
  security find-identity -v -p "$2" 2>/dev/null | grep -E "\"($1): " | head -1 || true
}
APP_LINE="$(identity_line 'Apple Distribution|3rd Party Mac Developer Application' codesigning)"
INSTALLER_LINE="$(identity_line 'Mac Installer Distribution|3rd Party Mac Developer Installer' basic)"
APP_IDENTITY="${APP_SIGN_IDENTITY:-$(echo "$APP_LINE" | grep -oE '"[^"]*"' | tr -d '"' || true)}"
APP_HASH="${APP_SIGN_HASH:-$(echo "$APP_LINE" | awk '{print $2}' || true)}"
INSTALLER_IDENTITY="${INSTALLER_SIGN_IDENTITY:-$(echo "$INSTALLER_LINE" | grep -oE '"[^"]*"' | tr -d '"' || true)}"
INSTALLER_HASH="${INSTALLER_SIGN_HASH:-$(echo "$INSTALLER_LINE" | awk '{print $2}' || true)}"
# Certificates can be made from a signing request in the browser, which is the
# only way when Xcode's UI will not launch (it refuses on a macOS newer than it
# shipped for, though its command line tools — all this build needs — still work).
certificate_help() {
  echo "" >&2
  echo "To make one without Xcode:" >&2
  echo "  1. ./newcert.sh $1     (writes a signing request to ~/GlassineSigning)" >&2
  echo "  2. developer.apple.com/account/resources/certificates/add → $2" >&2
  echo "     → upload the .csr it names → download the .cer" >&2
  echo "  3. ./newcert.sh $1 --import ~/Downloads/<the file>.cer" >&2
}
if [[ -z "$APP_IDENTITY" ]]; then
  echo "No 'Apple Distribution' certificate in your keychain." >&2
  certificate_help app "Apple Distribution"
  exit 1
fi
if [[ -z "$INSTALLER_IDENTITY" ]]; then
  echo "No 'Mac Installer Distribution' certificate in your keychain." >&2
  certificate_help installer "Mac Installer Distribution"
  exit 1
fi
# The Team ID is the certificate's Organizational Unit. The parenthetical in
# the certificate's name looks the same on distribution certificates but is the
# certificate's own ID on others, so read the OU and only fall back to the name.
read_team_id() {
  local cn="${APP_IDENTITY#\"}"; cn="${cn%\"}"
  security find-certificate -c "$cn" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null \
    | grep -oE 'OU ?= ?[A-Z0-9]+' | grep -oE '[A-Z0-9]{10}' | head -1 || true
}
TEAM_ID="${TEAM_ID:-$(read_team_id || true)}"
[[ -z "$TEAM_ID" ]] && TEAM_ID="$(echo "$APP_IDENTITY" | grep -oE '\(([A-Z0-9]+)\)$' | tr -d '()' || true)"
if [[ ! "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "Couldn't read the Team ID from '$APP_IDENTITY'. Set it by hand: TEAM_ID=XXXXXXXXXX ./appstore.sh $VERSION" >&2
  exit 1
fi
if [[ ! -f "$PROFILE" ]]; then
  echo "Provisioning profile not found at $PROFILE." >&2
  echo "developer.apple.com → Profiles → + → Mac App Store Connect → App ID $BUNDLE_ID → download, then save it there." >&2
  exit 1
fi
echo "▸ App identity:       $APP_IDENTITY  [$APP_HASH]"
echo "▸ Installer identity: $INSTALLER_IDENTITY  [$INSTALLER_HASH]"
echo "▸ Team ID:            $TEAM_ID"

# The profile has to be for this app and this team, and it has to grant every
# entitlement we are about to sign with. A profile only carries the capabilities
# the App ID had switched on when it was generated, so enabling iCloud after the
# fact silently leaves it out — and the build is not rejected until it has been
# uploaded. Check it here, where the fix is one page on developer.apple.com.
PP="$(mktemp -t glassine-profile).plist"
security cms -D -i "$PROFILE" > "$PP" 2>/dev/null || { echo "Couldn't read $PROFILE." >&2; exit 1; }
if ! grep -q "$TEAM_ID" "$PP"; then
  echo "The provisioning profile at $PROFILE is not for team $TEAM_ID." >&2
  exit 1
fi
missing=()
for key in $(grep -oE '<key>com\.apple\.(developer|security)\.[^<]+</key>' Resources/Glassine-AppStore.entitlements \
             | sed 's/<\/*key>//g' | grep -v '^com\.apple\.security\.' || true); do
  /usr/libexec/PlistBuddy -c "Print :Entitlements:$key" "$PP" >/dev/null 2>&1 || missing+=("$key")
done
rm -f "$PP"
if (( ${#missing[@]} )); then
  echo "The provisioning profile does not grant:" >&2
  printf '  %s\n' "${missing[@]}" >&2
  echo "" >&2
  echo "Turn the matching capability on for the App ID, then generate a NEW profile:" >&2
  echo "  1. developer.apple.com → Identifiers → $BUNDLE_ID → enable iCloud," >&2
  echo "     container $CONTAINER_ID (create it under Identifiers → iCloud Containers first)." >&2
  echo "  2. Profiles → the Glassine profile → Edit → Save (this regenerates it) → Download." >&2
  echo "  3. Replace $PROFILE with the new download." >&2
  echo "An existing profile is NOT updated when the App ID changes; it must be regenerated." >&2
  exit 1
fi
echo "▸ Profile grants every entitlement the app declares"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree has uncommitted changes. Commit or stash them first." >&2
  exit 1
fi

# --- Version bump ------------------------------------------------------------------------
BUILD_NUMBER="$(( $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST") + 1 ))"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"
echo "▸ Version $VERSION (build $BUILD_NUMBER)"

# --- Build the sandboxed flavor ------------------------------------------------------------
./build.sh --appstore >/dev/null
[[ -d "$APP" ]] || { echo "build.sh did not produce $APP" >&2; exit 1; }

# --- Provisioning profile + entitlements with the real Team ID ------------------------------
cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"
ENT="$(mktemp -t glassine-entitlements).plist"
sed "s/TEAM_ID_PLACEHOLDER/$TEAM_ID/g" Resources/Glassine-AppStore.entitlements > "$ENT"

# --- Sign ----------------------------------------------------------------------------------
echo "▸ Signing"
codesign --force --deep --options runtime --timestamp \
  --entitlements "$ENT" --sign "$APP_HASH" --identifier "$BUNDLE_ID" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "▸ Entitlements as signed:"
codesign -d --entitlements :- "$APP" 2>/dev/null | grep -E 'sandbox|icloud|ubiquity|team-identifier|application-identifier' || true
rm -f "$ENT"

# --- Package -------------------------------------------------------------------------------
mkdir -p "$DIST"
rm -f "$PKG"
echo "▸ Building installer package"
productbuild --component "$APP" /Applications --sign "$INSTALLER_HASH" "$PKG"
pkgutil --check-signature "$PKG" | head -3
echo "▸ $PKG is ready"

# --- Commit --------------------------------------------------------------------------------
if [[ $DRY_RUN -eq 1 ]]; then
  echo "▸ Dry run: leaving the version bump uncommitted. Undo with: git checkout -- $PLIST"
else
  git add "$PLIST"
  git commit -q -m "App Store build $VERSION ($BUILD_NUMBER)"
  echo "▸ Committed the version bump (push when you like)"
fi

# --- Hand off to Transporter -----------------------------------------------------------------
cat <<EOF

Next: upload with Transporter.
  1. Open Transporter (App Store → search "Transporter"; it is Apple's, and free).
  2. Sign in with your Apple ID, drop $PKG on the window, click Deliver.
  3. App Store Connect → Glassine Writer → TestFlight to try it, or → the version page → add the build → Submit for Review.
EOF
if [[ -d /Applications/Transporter.app ]]; then
  open -a Transporter "$PKG" || true
fi
