#!/usr/bin/env bash
# The pictures on glassine.ink, in the README and in the manual, taken by the
# direct build of itself against a temporary copy of the showcase library.
#
#   ./build.sh && site/screenshots.sh            # all eight
#   ONLY=writing site/screenshots.sh              # one of them
#
# Each picture is one launch with everything on the command line — settings,
# view, caret, a selection or a slash — and the full composite capture, backdrop
# beneath, so the glass is real (macOS counts that as screen recording and says
# so with a notice; the pictures are worth it). The window comes to the front
# while it is taken, so keep your hands off the keyboard for a minute.
#
# Output: 1440×900 JPEGs in site/, docs/screenshots/ and docs/site/images/.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="$PWD/build/Glassine.app"
BIN="$APP/Contents/MacOS/Glassine"
SRC="$PWD/docs/appstore/library"
LIB=/tmp/glassine-site/Glassine      # the folder's name shows in the sidebar's footer
T="$(getconf DARWIN_USER_TEMP_DIR)glassine-shots"
OUT="$PWD/dist/site-shots"
WINDOW="1440x900"

[[ -x "$BIN" ]] || { echo "No build. Run ./build.sh first." >&2; exit 1; }
pkill -f "$BIN" 2>/dev/null || true

# --- The library, with today's dates filled in ------------------------------------------------
rm -rf "$(dirname "$LIB")"; mkdir -p "$LIB/Daily"
cp -R "$SRC"/Essays "$SRC"/Notes "$SRC"/Ideas "$LIB"/
for f in "$SRC"/Daily/*.md; do
  ago=$(basename "$f" .md)
  title=$(date -v-"${ago}"d "+%A, %B %e, %Y" | sed 's/  */ /g')
  sed "s/{{DATE}}/$title/" "$f" > "$LIB/Daily/$title.md"
  touch -t "$(date -v-"${ago}"d "+%Y%m%d1400")" "$LIB/Daily/$title.md"
done
today=$(date "+%B %-d, %Y")
sed -i '' "s/@September 6, 2026/@$today/" "$LIB/Notes/Field Notes.md"
i=0
for rel in "Ideas/Names for the Boat.md" "Notes/Reading List.md" "Ideas/Small Rituals.md" \
           "Ideas/A Letter to September.md" "Notes/Launch Checklist.md" "Notes/Field Notes.md" "Essays/On Writing Slowly.md"; do
  touch -t "$(date -v-$((7 - i))H "+%Y%m%d%H%M")" "$LIB/$rel"; i=$((i + 1))
done
mkdir -p "$OUT" "$T"; : > "$T/log.txt"

offset_of() {
  swift - "$1" "$2" 2>/dev/null <<'SWIFT'
import Foundation
let text = (try? String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)) ?? ""
if let r = text.range(of: CommandLine.arguments[2]) {
    print(text.utf16.distance(from: text.utf16.startIndex, to: r.lowerBound.samePosition(in: text.utf16)!))
} else { print(0) }
SWIFT
}

# shot <name> <settings json> [view: review|daily|-] [caret] [settle seconds] [extra args…]
shot() {
  local name=$1 json=$2 view=${3:-} caret=${4:-} settle=${5:-3}
  shift 5 2>/dev/null || shift $#
  [[ -n "${ONLY:-}" && "$ONLY" != "$name" ]] && return 0
  local args=(-glassine.shoot "$name.png" -glassine.launchWindow "$WINDOW" -glassine.shootDelay "$settle" -glassine.shootCapture 1
              -glassine.launchSettings "$(printf '%s' "$json" | base64 | tr -d '\n')")
  [[ -n "$view" && "$view" != "-" ]] && args+=(-glassine.launchView "$view")
  [[ -n "$caret" ]] && args+=(-glassine.launchCaret "$caret")
  args+=("$@")
  rm -f "$T/$name.png" "$T/$name.png.status"
  open -n "$APP" --args "${args[@]}"
  local w=0
  until [[ -f "$T/$name.png.status" ]]; do sleep 0.5; w=$((w + 1)); (( w > 120 )) && { echo "$name: no status" >&2; exit 1; }; done
  local status; status=$(cat "$T/$name.png.status")
  [[ "$status" == "ok" ]] || { echo "$name: $status" >&2; exit 1; }
  while pgrep -f "$BIN" >/dev/null; do sleep 0.25; done
  for dir in site docs/screenshots docs/site/images; do
    [[ -f "$dir/$name.jpg" ]] && chmod u+w "$dir/$name.jpg"
    sips -z 900 1440 -s format jpeg "$T/$name.png" --out "$dir/$name.jpg" >/dev/null
  done
  cp "$T/$name.png" "$OUT/$name.png"
  echo "* $name"
}

base='"fontSize":19,"columnWidth":720,"sidebarVisible":true,"sidebarWidth":270,"expandedFolders":["Essays","Notes","Ideas","Daily"],"starred":["Essays/On Writing Slowly.md","Notes/Launch Checklist.md"],"reviewStyle":"glass","showCounter":true,"appearanceMode":"fixed","libraryPath":"'"$LIB"'"'
plain='"typewriterMode":false,"focusMode":false'
ESSAY="$LIB/Essays/On Writing Slowly.md"
NOTES="$LIB/Notes/Field Notes.md"
TOP=$(offset_of "$ESSAY" "Most tools for writing")
MID=$(offset_of "$ESSAY" "A slow writer reads")
SEL=$(offset_of "$NOTES" "for the record")
BLANK=$(( $(offset_of "$NOTES" "Next week") - 1 ))

shot editor  '{'"$base"','"$plain"',"themeID":"dusk","lastOpenedDocument":"Essays/On Writing Slowly.md"}' - "$TOP" 3
shot focus   '{'"$base"',"typewriterMode":true,"focusMode":true,"focusDimming":0.35,"themeID":"dusk","lastOpenedDocument":"Essays/On Writing Slowly.md"}' - "$MID" 3
shot review  '{'"$base"','"$plain"',"themeID":"dusk","lastOpenedDocument":"Essays/On Writing Slowly.md"}' review "" 8
shot library '{'"$base"','"$plain"',"themeID":"dusk","lastOpenedDocument":null}' - "" 3
shot daily   '{'"$base"','"$plain"',"themeID":"dusk","lastOpenedDocument":"Essays/On Writing Slowly.md"}' daily "" 4
shot light   '{'"$base"','"$plain"',"themeID":"paper","lastOpenedDocument":"Notes/Launch Checklist.md"}' - "" 3
shot writing '{'"$base"','"$plain"',"hideSyntax":true,"themeID":"dusk","lastOpenedDocument":"Notes/Field Notes.md"}' - "$SEL" 4 -glassine.shootSelect "$SEL,14"
shot slash   '{'"$base"',"typewriterMode":true,"focusMode":false,"hideSyntax":true,"themeID":"dusk","lastOpenedDocument":"Notes/Field Notes.md"}' - "$BLANK" 4 -glassine.shootSlash 1

rm -rf "$(dirname "$LIB")"
echo "* Done: pictures in site/, docs/screenshots/ and docs/site/images/"
