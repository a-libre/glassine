#!/bin/bash
# Generates the project, builds for the simulator, installs and launches on a
# simulator (booted headless), and takes a picture.
#   ios/build-sim.sh                       → build/ios-sim.log, build/ios-sim.png
#   DEVICE="iPad Pro 13-inch (M5)" NAME=ipad ios/build-sim.sh
#   SKIP_BUILD=1 NAME=editor SETTINGS='{"sidebarVisible":false,…}' ios/build-sim.sh
# SETTINGS is a SettingsData JSON for this launch only (the Mac's
# -glassine.launchSettings); a "libraryPath" in it may name a folder on this
# Mac, which a simulator can read. ARGS are further launch arguments.
cd "$(dirname "$0")/.."
export PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin
DEVICE="${DEVICE:-iPhone 17 Pro}"
NAME="${NAME:-sim}"
LOG=build/ios-sim.log
mkdir -p build; : > "$LOG"
if [[ -z "${SKIP_BUILD:-}" ]]; then
  # The project is regenerated only when it could have changed — project.yml, or a
  # Swift file added or removed — so an Xcode window open on it is not made to
  # reload for nothing.
  LIST="$(find Sources/Shared Sources/iOS -name '*.swift' | sort)"
  if [[ ! -d ios/Glassine.xcodeproj || ios/project.yml -nt ios/Glassine.xcodeproj/project.pbxproj \
        || "$LIST" != "$(cat .build-ios/sources.list 2>/dev/null)" ]]; then
    (cd ios && xcodegen generate) >> "$LOG" 2>&1 || { echo "exit xcodegen" >> "$LOG"; exit 1; }
    mkdir -p .build-ios; printf '%s' "$LIST" > .build-ios/sources.list
  fi
  xcodebuild -project ios/Glassine.xcodeproj -scheme Glassine -configuration Debug \
    -destination "platform=iOS Simulator,name=$DEVICE" -derivedDataPath .build-ios \
    CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E 'error:|BUILD|\*\*' >> "$LOG"
  grep -q 'BUILD SUCCEEDED' "$LOG" || { echo "exit build" >> "$LOG"; exit 1; }
fi
APP=.build-ios/Build/Products/Debug-iphonesimulator/Glassine.app
[[ -d "$APP" ]] || { echo "exit noapp" >> "$LOG"; exit 1; }
xcrun simctl boot "$DEVICE" >> "$LOG" 2>&1 || true
xcrun simctl bootstatus "$DEVICE" -b > /dev/null 2>&1
xcrun simctl install "$DEVICE" "$APP" >> "$LOG" 2>&1
xcrun simctl terminate "$DEVICE" com.alexlibre.glassine > /dev/null 2>&1 || true
LAUNCH=()
if [[ -n "${SETTINGS:-}" ]]; then
  LAUNCH+=(-glassine.launchSettings "$(printf '%s' "$SETTINGS" | base64 | tr -d '\n')")
fi
# shellcheck disable=SC2206
LAUNCH+=(${ARGS:-})
# TYPE is text for the simulator's script to type (\n for Return).
if [[ -n "${TYPE:-}" ]]; then LAUNCH+=(-glassine.typeText "$TYPE"); fi
xcrun simctl launch "$DEVICE" com.alexlibre.glassine "${LAUNCH[@]}" >> "$LOG" 2>&1
sleep "${SETTLE:-6}"
xcrun simctl io "$DEVICE" screenshot "build/ios-$NAME.png" >> "$LOG" 2>&1
echo "exit 0" >> "$LOG"
