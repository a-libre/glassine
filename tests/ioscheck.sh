#!/bin/bash
# Typechecks the shared code and the iOS shell against the iOS simulator SDK,
# without building an app: the quick answer to "does Shared still compile for iOS?"
#   tests/ioscheck.sh                     → build/ioscheck.log (last line: "exit N")
#   tests/ioscheck.sh Sources/Shared      just those folders or files
cd "$(dirname "$0")/.."
export PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin
LOG=build/ioscheck.log
: > "$LOG"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
[[ $# -gt 0 ]] || set -- Sources/Shared Sources/iOS
FILES=()
while IFS= read -r f; do FILES+=("$f"); done < <(find "$@" -name '*.swift' | grep -vE "${EXCLUDE:-^$}" | sort)
xcrun --sdk iphonesimulator swiftc -typecheck -wmo -sdk "$SDK" \
  -target arm64-apple-ios17.0-simulator -module-name Glassine -DAPPSTORE \
  "${FILES[@]}" >> "$LOG" 2>&1
echo "exit $?" >> "$LOG"
