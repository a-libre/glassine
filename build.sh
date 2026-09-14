#!/bin/bash
# Builds Glassine.app from the Swift package. No Xcode project needed.
#
#   ./build.sh            release build → build/Glassine.app (the direct-download flavor)
#   ./build.sh --run      build, then open the app
#   ./build.sh --install  build, copy to /Applications, and open it
#   ./build.sh --debug    debug build (faster compile)
#   ./build.sh --appstore the App Store flavor: sandboxed, without Sparkle (the store updates it).
#                         Ad-hoc signed here, so no iCloud container — the library
#                         goes to the sandbox's Documents folder or a folder you pick.
#                         appstore.sh signs it for real.
#   ./build.sh --demo     "Glassine Demo.app": the app under an identity of its own, so its
#                         settings are its own, with the showcase pages of docs/appstore/library
#                         for a library (in ~/Library/Application Support/Glassine Demo) and no
#                         updater — for pictures and recordings that show nobody's real notes.
#                         --install puts it in /Applications beside Glassine; both can run at once.
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
    --demo) FLAVOR="demo" ;;
  esac
done
BUNDLE_NAME="$APP_NAME"
[[ "$FLAVOR" == "demo" ]] && BUNDLE_NAME="$APP_NAME Demo"

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
  # Package.swift reads this and leaves Sparkle out: the store is the updater there.
  export GLASSINE_APPSTORE=1
elif [[ "$FLAVOR" == "demo" ]]; then
  SWIFT_ARGS+=(--scratch-path .build-demo -Xswiftc -DDEMO)
  # No updater in the demonstration copy either; Sparkle stays out the same way.
  export GLASSINE_APPSTORE=1
else
  # The direct flavor carries Sparkle in Contents/Frameworks; the executable looks there.
  SWIFT_ARGS+=(-Xlinker -rpath -Xlinker @executable_path/../Frameworks)
fi

# Sparkle's pieces are signed one by one, innermost first, the way its
# documentation asks; a --deep signature of the app would hand them the app's
# identifier. $1 is the identity; anything after it goes to codesign as well.
sign_sparkle() {
  local identity="$1"; shift
  local fw="$APP/Contents/Frameworks/Sparkle.framework"
  [[ -d "$fw" ]] || return 0
  local piece
  for piece in "$fw/Versions/B/XPCServices/Installer.xpc" "$fw/Versions/B/XPCServices/Downloader.xpc" \
               "$fw/Versions/B/Autoupdate" "$fw/Versions/B/Updater.app" "$fw"; do
    [[ -e "$piece" ]] || continue
    codesign --force --sign "$identity" --preserve-metadata=entitlements "$@" "$piece" 2>&1 | grep -v 'replacing existing signature' || true
  done
}

echo "▸ Compiling ($CONFIG, $FLAVOR)…"
swift build "${SWIFT_ARGS[@]}" 2>&1 | grep -v '^\[' || true
BIN_DIR="$(swift build "${SWIFT_ARGS[@]}" --show-bin-path)"
if [[ ! -x "$BIN_DIR/$APP_NAME" ]]; then
  echo "Build failed — see errors above." >&2
  exit 1
fi

APP="build/$BUNDLE_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [[ "$FLAVOR" == "appstore" ]]; then
  # No updater in the store flavor, so the keys that would point one at the feed go too.
  for key in SUFeedURL SUPublicEDKey SUEnableAutomaticChecks SUScheduledCheckInterval; do
    /usr/libexec/PlistBuddy -c "Delete :$key" "$APP/Contents/Info.plist" >/dev/null 2>&1 || true
  done
elif [[ "$FLAVOR" == "demo" ]]; then
  # Its own identifier, so its settings, window and themes are its own; "Glassine
  # Demo" in Finder and the Dock, plain Glassine in the menu bar; no updater; and
  # not an editor of anybody's files, so Finder's Open With lists Glassine once.
  PLIST="$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.alexlibre.glassine.demo" "$PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $BUNDLE_NAME" "$PLIST"
  for key in SUFeedURL SUPublicEDKey SUEnableAutomaticChecks SUScheduledCheckInterval CFBundleDocumentTypes UTImportedTypeDeclarations UTExportedTypeDeclarations; do
    /usr/libexec/PlistBuddy -c "Delete :$key" "$PLIST" >/dev/null 2>&1 || true
  done
  mkdir -p "$APP/Contents/Resources/DemoLibrary"
  cp -R docs/appstore/library/. "$APP/Contents/Resources/DemoLibrary/"
else
  SPARKLE="$(find .build/artifacts -type d -name Sparkle.framework -path '*macos*' -print -quit 2>/dev/null || true)"
  if [[ ! -d "$SPARKLE" ]]; then
    echo "Sparkle.framework is not under .build/artifacts — run: swift package resolve" >&2
    exit 1
  fi
  mkdir -p "$APP/Contents/Frameworks"
  ditto "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"
fi

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
# The dark icon, for the Dock when the Mac is in dark mode (Support/AppIcon.swift).
if [[ -d Resources/AppIcon-Dark.iconset ]]; then
  if [[ ! -f Resources/AppIcon-Dark.icns || -n "$(find Resources/AppIcon-Dark.iconset -newer Resources/AppIcon-Dark.icns -print -quit)" ]]; then
    iconutil -c icns Resources/AppIcon-Dark.iconset -o Resources/AppIcon-Dark.icns
  fi
  cp Resources/AppIcon-Dark.icns "$APP/Contents/Resources/AppIcon-Dark.icns"
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
elif [[ "$FLAVOR" == "demo" ]]; then
  codesign --force --sign - --identifier com.alexlibre.glassine.demo "$APP" >/dev/null 2>&1
else
  sign_sparkle -
  codesign --force --sign - --identifier com.alexlibre.glassine "$APP" >/dev/null 2>&1
fi
echo "▸ Built $APP ($FLAVOR)"

if [[ $INSTALL -eq 1 ]]; then
  # A running copy would keep executing the old code (and fight the copy); ask it to quit.
  if [[ "$FLAVOR" == "demo" ]]; then
    pkill -f "/$BUNDLE_NAME.app/Contents/MacOS/" 2>/dev/null || true
  else
    osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
  fi
  sleep 1
  rm -rf "/Applications/$BUNDLE_NAME.app"
  cp -R "$APP" "/Applications/$BUNDLE_NAME.app"
  echo "▸ Installed /Applications/$BUNDLE_NAME.app"
  APP="/Applications/$BUNDLE_NAME.app"
fi

if [[ $RUN -eq 1 ]]; then
  open "$APP"
fi
