#!/bin/bash
# Generates the project, builds for the simulator, installs and launches on an
# iPhone simulator (booted headless), and takes a picture.
#   ios/build-sim.sh [device name]      → build/ios-sim.log, build/ios-sim.png
cd "$(dirname "$0")/.."
export PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin
DEVICE="${1:-iPhone 17 Pro}"
LOG=build/ios-sim.log
mkdir -p build; : > "$LOG"
(cd ios && xcodegen generate) >> "$LOG" 2>&1 || { echo "exit xcodegen" >> "$LOG"; exit 1; }
xcodebuild -project ios/Glassine.xcodeproj -scheme Glassine -configuration Debug \
  -destination "platform=iOS Simulator,name=$DEVICE" -derivedDataPath .build-ios \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E 'error:|warning: unre|BUILD|\*\*' >> "$LOG"
APP=.build-ios/Build/Products/Debug-iphonesimulator/Glassine.app
if [[ ! -d "$APP" ]]; then echo "exit build" >> "$LOG"; exit 1; fi
xcrun simctl boot "$DEVICE" >> "$LOG" 2>&1 || true
xcrun simctl bootstatus "$DEVICE" -b >> "$LOG" 2>&1
xcrun simctl install "$DEVICE" "$APP" >> "$LOG" 2>&1
xcrun simctl terminate "$DEVICE" com.alexlibre.glassine >> "$LOG" 2>&1 || true
xcrun simctl launch "$DEVICE" com.alexlibre.glassine >> "$LOG" 2>&1
sleep "${SETTLE:-6}"
xcrun simctl io "$DEVICE" screenshot build/ios-sim.png >> "$LOG" 2>&1
echo "exit 0" >> "$LOG"
