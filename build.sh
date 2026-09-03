#!/bin/bash
# Builds Glassine.app from the Swift package. No Xcode project needed.
#
#   ./build.sh            release build → build/Glassine.app (the direct-download flavor)
#   ./build.sh --run      build, then open the app
#   ./build.sh --install  build, copy to /Applications, and open it
#   ./build.sh --debug    debug build (faster compile)
#   ./build.sh --appstore the App Store flavor: sandboxed, no GitHub update check.
#                         Ad-hoc signed here, so no iCloud container — the library
#                         goes to the sandbox's Documents folder or a folder you pick.
#                         appstore.sh signs it for real.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Glassine"
CONFIG="release"
RUN=0
INSTALL=0
FLAVOR="direct"
for arg in "$@"; do
  case "$arg" in
    --debug) CONFIG="debug" ;;
    --run) RUN=1 ;;
    --install) INSTALL=1; RUN=1 ;;
    --appstore) FLAVOR="appstore" ;;
  esac
done

if ! xcode-select -p >/dev/null 2>&1; then
  echo "Xcode (or its command line tools) is required. Install Xcode from the App Store, then run: sudo xcode-select -s /Applications/Xcode.app" >&2
  exit 1
fi

# Each flavor keeps its own build folder so switching does not force a full rebuild.
SWIFT_ARGS=(-c "$CONFIG")
ENTITLEMENTS=""
if [[ "$FLAVOR" == "appstore" ]]; then
  SWIFT_ARGS+=(--scratch-path .build-appstore -Xswiftc -DAPPSTORE)
  ENTITLEMENTS="Resources/Glassine-Sandbox-Dev.entitlements"
fi

echo "▸ Compiling ($CONFIG, $FLAVOR)…"
swift build "${SWIFT_ARGS[@]}" 2>&1 | grep -v '^\[' || true
BIN_DIR="$(swift build "${SWIFT_ARGS[@]}" --show-bin-path)"
if [[ ! -x "$BIN_DIR/$APP_NAME" ]]; then
  echo "Build failed — see errors above." >&2
  exit 1
fi

APP="build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Icon: build .icns from the iconset when it is missing or older than any of
# the iconset's files, so a regenerated icon is picked up without a manual rm.
if [[ -d Resources/AppIcon.iconset ]]; then
  if [[ ! -f Resources/AppIcon.icns || -n "$(find Resources/AppIcon.iconset -newer Resources/AppIcon.icns -print -quit)" ]]; then
    iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
  fi
fi
if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
if [[ -f Resources/wordmark.png ]]; then
  cp Resources/wordmark.png "$APP/Contents/Resources/wordmark.png"
fi

# Everything in the bundle must be readable by any user, or the code signature
# cannot be verified at launch and the App Store refuses the package. cp keeps
# the source's mode, so a resource that arrived with owner-only permissions
# would otherwise carry them straight in. Directories and the executable keep
# their execute bit; nothing else gains one.
chmod -R a+rX "$APP"
# Downloaded files carry a quarantine attribute that cp preserves and the App
# Store rejects; nothing in a bundle needs any extended attribute.
xattr -cr "$APP" 2>/dev/null || true

# Ad-hoc signature so macOS treats it as a proper local app (stable identity for
# permissions). The App Store flavor also gets the sandbox, so it behaves here as
# it will in the store.
if [[ -n "$ENTITLEMENTS" ]]; then
  codesign --force --deep --sign - --identifier com.alexlibre.glassine --entitlements "$ENTITLEMENTS" "$APP" 2>&1 | grep -v 'replacing existing signature' || true
  codesign -d --entitlements - "$APP" 2>/dev/null | grep -q 'app-sandbox' || { echo "Sandbox entitlements did not apply — see the codesign output above." >&2; exit 1; }
else
  codesign --force --deep --sign - --identifier com.alexlibre.glassine "$APP" >/dev/null 2>&1
fi
echo "▸ Built $APP ($FLAVOR)"

if [[ $INSTALL -eq 1 ]]; then
  # A running copy would keep executing the old code (and fight the copy); ask it to quit.
  osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
  sleep 1
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP" "/Applications/$APP_NAME.app"
  echo "▸ Installed /Applications/$APP_NAME.app"
  APP="/Applications/$APP_NAME.app"
fi

if [[ $RUN -eq 1 ]]; then
  open "$APP"
fi
