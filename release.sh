#!/bin/bash
# Cuts a signed, notarized Glassine release and publishes it to GitHub.
#
#   ./release.sh 0.2.0            full release: tag, build, sign, notarize, dmg, GitHub release
#   ./release.sh 0.2.0 --dry-run  everything except git push / GitHub release
#
# One-time setup (see RELEASING.md):
#   1. Xcode → Settings → Accounts → your Apple ID → Manage Certificates → + → "Developer ID Application"
#   2. xcrun notarytool store-credentials "glassine-notary" --apple-id you@example.com --team-id TEAMID
#      (it asks for an app-specific password from appleid.apple.com)
#   3. Optional: brew install gh && gh auth login   (for automatic GitHub Releases)
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:-}"
DRY_RUN=0
[[ "${2:-}" == "--dry-run" ]] && DRY_RUN=1
if [[ -z "$VERSION" || ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "usage: ./release.sh X.Y.Z [--dry-run]" >&2
  exit 1
fi

APP_NAME="Glassine"
BUNDLE_ID="com.alexlibre.glassine"
NOTARY_PROFILE="${NOTARY_PROFILE:-glassine-notary}"
PLIST="Resources/Info.plist"
DIST="dist"
APP="build/$APP_NAME.app"
DMG="$DIST/$APP_NAME-$VERSION.dmg"
ZIP="$DIST/$APP_NAME-$VERSION.zip"

# --- Preflight --------------------------------------------------------------------------
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')}"
if [[ -z "$IDENTITY" ]]; then
  echo "No 'Developer ID Application' certificate in your keychain. Create one in Xcode → Settings → Accounts → Manage Certificates." >&2
  exit 1
fi
echo "▸ Signing identity: $IDENTITY"

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "Notary credentials not found. Run: xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --apple-id <apple-id> --team-id <team-id>" >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree has uncommitted changes. Commit or stash them first." >&2
  exit 1
fi

# --- Version bump ------------------------------------------------------------------------
BUILD_NUMBER="$(( $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST") + 1 ))"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"
echo "▸ Version $VERSION (build $BUILD_NUMBER)"

# --- Build --------------------------------------------------------------------------------
./build.sh >/dev/null
[[ -d "$APP" ]] || { echo "build.sh did not produce $APP" >&2; exit 1; }

# --- Sign (hardened runtime + secure timestamp, required for notarization) -----------------
echo "▸ Signing"
codesign --force --deep --options runtime --timestamp \
  --entitlements Resources/Glassine.entitlements \
  --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

# --- Notarize the app, staple --------------------------------------------------------------
mkdir -p "$DIST"
rm -f "$ZIP" "$DMG"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "▸ Notarizing app (this usually takes a few minutes)"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"

# --- Disk image ----------------------------------------------------------------------------
echo "▸ Building disk image"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"
rm -rf "$STAGE"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
echo "▸ Notarizing disk image"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature -v "$DMG"
rm -f "$ZIP"
echo "▸ $DMG is signed, notarized and stapled"

# --- Commit, tag, publish -------------------------------------------------------------------
git add "$PLIST"
git commit -q -m "Release $VERSION"
git tag -a "v$VERSION" -m "Glassine $VERSION"

if [[ $DRY_RUN -eq 1 ]]; then
  echo "▸ Dry run: not pushing. Undo with: git reset --hard HEAD~1 && git tag -d v$VERSION"
  exit 0
fi

git push origin main --tags
if command -v gh >/dev/null 2>&1; then
  gh release create "v$VERSION" "$DMG" --title "Glassine $VERSION" --generate-notes
  echo "▸ Published: https://github.com/a-libre/glassine/releases/tag/v$VERSION"
else
  echo "▸ Tag pushed. GitHub CLI isn't installed, so create the release by hand:"
  echo "    https://github.com/a-libre/glassine/releases/new?tag=v$VERSION"
  echo "  and attach $DMG. (Or: brew install gh && gh auth login, and next time this is automatic.)"
fi
