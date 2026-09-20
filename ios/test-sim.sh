#!/bin/bash
# Runs the UI tests on a simulator (booted headless).
#   ios/test-sim.sh                                   all of them  → build/ios-test.log
#   ios/test-sim.sh EditorTests/testTypewriterHoldsStillWhileTyping
#   DEVICE="iPad Pro 11-inch (M5)" ios/test-sim.sh
cd "$(dirname "$0")/.."
export PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin
DEVICE="${DEVICE:-iPhone 16e}"
LOG=build/ios-test.log
mkdir -p build .build-ios; : > "$LOG"
LIST="$(find Sources/Shared Sources/iOS ios/UITests -name '*.swift' | sort)"
if [[ ! -d ios/Glassine.xcodeproj || ios/project.yml -nt ios/Glassine.xcodeproj/project.pbxproj \
      || "$LIST" != "$(cat .build-ios/test-sources.list 2>/dev/null)" ]]; then
  (cd ios && xcodegen generate) >> "$LOG" 2>&1 || { echo "exit xcodegen" >> "$LOG"; exit 1; }
  printf '%s' "$LIST" > .build-ios/test-sources.list
  find Sources/Shared Sources/iOS -name '*.swift' | sort | tr -d '\n' > /dev/null
fi
ONLY=()
[[ -n "${1:-}" ]] && ONLY=(-only-testing:"GlassineUITests/$1")
xcodebuild test -project ios/Glassine.xcodeproj -scheme Glassine -configuration Debug \
  -destination "platform=iOS Simulator,name=$DEVICE" -derivedDataPath .build-ios "${ONLY[@]}" > build/ios-test-full.log 2>&1
STATUS=$?
grep -E 'error:|TRACE|Test Case|Test Suite .* (passed|failed)|\*\* TEST' build/ios-test-full.log >> "$LOG"
echo "exit $STATUS" >> "$LOG"
