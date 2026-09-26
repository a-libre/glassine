#!/usr/bin/env bash
# The app photographs its own glass for the aurora icon: Dusk over Aurora, the
# sidebar hidden, a blank page, the caret not blinking. Writes
# Resources/aurora.png; then `python3 Resources/make_icon.py --aurora` draws
# the icon on it. Run against the installed app so nothing else has to build:
#   tests/shot-icon.sh [/Applications/Glassine.app]
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:-/Applications/Glassine.app}"
LIB=/tmp/glassine-shot-library-icon
T="$(getconf DARWIN_USER_TEMP_DIR)glassine-shots"
rm -rf "$LIB"; mkdir -p "$LIB"; printf '\n' > "$LIB/Blank.md"
mkdir -p "$T"
name=icon-aurora
rm -f "$T/$name.png" "$T/$name.png.status"
json='{"sidebarVisible":false,"typewriterMode":false,"focusMode":false,"showCounter":false,"themeID":"dusk","appearanceMode":"fixed","backdrop":"aurora","backdropGrain":0.08,"caretBlink":"none","libraryPath":"'"$LIB"'","lastOpenedDocument":"Blank.md"}'
b64=$(printf '%s' "$json" | base64 | tr -d '\n')
open -n "$APP" --args -glassine.shoot "$name.png" -glassine.launchWindow 1200x860 -glassine.shootDelay 5 -glassine.launchSettings "$b64"
w=0; until [[ -f "$T/$name.png.status" ]]; do sleep 0.5; w=$((w+1)); (( w > 60 )) && { echo "no status"; exit 1; }; done
cat "$T/$name.png.status"; echo
cp "$T/$name.png" Resources/aurora.png
echo "wrote Resources/aurora.png"
