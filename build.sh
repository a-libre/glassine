#!/bin/bash
# Builds Glassine.app from the Swift package. No Xcode project needed.
#
#   ./build.sh            release build → build/Glassine.app
#   ./build.sh --run      build, then open the app
#   ./build.sh --install  build, copy to /Applications, and open it
#   ./build.sh --debug    debug build (faster compile)
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Glassine"
CONFIG="release"
RUN=0
INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --debug) CONFIG="debug" ;;
    --run) RUN=1 ;;
    --install) INSTALL=1; RUN=1 ;;
  esac
done

if ! xcode-select -p >/dev/null 2>&1; then
  echo "Xcode (or its command line tools) is required. Install Xcode from the App Store, then run: sudo xcode-select -s /Applications/Xcode.app" >&2
  exit 1
fi

echo "▸ Compiling ($CONFIG)…"
swift build -c "$CONFIG" 2>&1 | grep -v '^\[' || true
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
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

# Icon: build .icns from the iconset if needed.
if [[ ! -f Resources/AppIcon.icns && -d Resources/AppIcon.iconset ]]; then
  iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
fi
if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
if [[ -f Resources/wordmark.png ]]; then
  cp Resources/wordmark.png "$APP/Contents/Resources/wordmark.png"
fi

# Ad-hoc signature so macOS treats it as a proper local app (stable identity for permissions).
codesign --force --deep --sign - --identifier com.alexlibre.glassine "$APP" >/dev/null 2>&1
echo "▸ Built $APP"

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
