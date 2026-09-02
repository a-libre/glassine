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
#   2. Xcode → Settings → Accounts → Manage Certificates → + → "Apple Distribution"
#      and + → "Mac Installer Distribution".
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
PLIST="Resources/Info.plist"
PROFILE="${PROVISIONING_PROFILE:-Resources/Glassine-AppStore.provisionprofile}"
DIST="dist"
APP="build/$APP_NAME.app"
PKG="$DIST/$APP_NAME-$VERSION-AppStore.pkg"

# --- Preflight --------------------------------------------------------------------------
find_identity() {
  # $1: a pattern like "Apple Distribution|3rd Party Mac Developer Application"
  security find-identity -v -p codesigning 2>/dev/null | grep -oE "\"($1): [^\"]*\"" | head -1 | tr -d '"'
}
APP_IDENTITY="${APP_SIGN_IDENTITY:-$(find_identity 'Apple Distribution|3rd Party Mac Developer Application')}"
INSTALLER_IDENTITY="${INSTALLER_SIGN_IDENTITY:-$(security find-identity -v 2>/dev/null | grep -oE '"(Mac Installer Distribution|3rd Party Mac Developer Installer): [^"]*"' | head -1 | tr -d '"')}"
if [[ -z "$APP_IDENTITY" ]]; then
  echo "No 'Apple Distribution' certificate in your keychain. Xcode → Settings → Accounts → Manage Certificates → + → Apple Distribution." >&2
  exit 1
fi
if [[ -z "$INSTALLER_IDENTITY" ]]; then
  echo "No 'Mac Installer Distribution' certificate in your keychain. Xcode → Settings → Accounts → Manage Certificates → + → Mac Installer Distribution." >&2
  exit 1
fi
TEAM_ID="$(echo "$APP_IDENTITY" | grep -oE '\(([A-Z0-9]+)\)$' | tr -d '()')"
if [[ -z "$TEAM_ID" ]]; then
  echo "Couldn't read the Team ID from the identity '$APP_IDENTITY'." >&2
  exit 1
fi
if [[ ! -f "$PROFILE" ]]; then
  echo "Provisioning profile not found at $PROFILE." >&2
  echo "developer.apple.com → Profiles → + → Mac App Store Connect → App ID $BUNDLE_ID → download, then save it there." >&2
  exit 1
fi
echo "▸ App identity:       $APP_IDENTITY"
echo "▸ Installer identity: $INSTALLER_IDENTITY"
echo "▸ Team ID:            $TEAM_ID"

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
  --entitlements "$ENT" --sign "$APP_IDENTITY" --identifier "$BUNDLE_ID" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "▸ Entitlements as signed:"
codesign -d --entitlements :- "$APP" 2>/dev/null | grep -E 'sandbox|icloud|ubiquity|team-identifier|application-identifier' || true
rm -f "$ENT"

# --- Package -------------------------------------------------------------------------------
mkdir -p "$DIST"
rm -f "$PKG"
echo "▸ Building installer package"
productbuild --component "$APP" /Applications --sign "$INSTALLER_IDENTITY" "$PKG"
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
