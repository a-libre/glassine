#!/usr/bin/env bash
# App Store screenshots, taken by the sandboxed build of itself.
#
#   ./build.sh --appstore && docs/appstore/screenshots.sh
#
# The app's sandbox container is backed up, filled with the showcase library in
# docs/appstore/library, and put back the way it was. Each picture is one launch
# of the app with everything it needs on the command line — settings, which view,
# where the caret goes — and the app photographs its own window and quits (see
# Sources/Glassine/Support/ScreenshotMode.swift). An app may capture its own
# window without any permission, so this runs from anywhere, with no prompts.
#
# Output: dist/screenshots/*.png at 2880×1800, one of the four sizes App Store
# Connect accepts for macOS, opaque, straight from the window server — and
# log.txt, whatever the app noted while taking them, for this run only.
set -euo pipefail
cd "$(dirname "$0")/../.."

APP="$PWD/build/Glassine.app"
BIN="$APP/Contents/MacOS/Glassine"
LIB="$PWD/docs/appstore/library"
CONTAINER="$HOME/Library/Containers/com.alexlibre.glassine/Data"
DOCS="$CONTAINER/Documents"
PREFS="$CONTAINER/Library/Preferences/com.alexlibre.glassine"   # a defaults domain given by path
SHOTS="$CONTAINER/tmp/glassine-shots"                          # where the app can write
OUT="$PWD/dist/screenshots"
WINDOW="1440x900"                                             # points; 2880×1800 pixels at 2x

[[ -x "$BIN" ]] || { echo "No sandboxed build. Run ./build.sh --appstore first." >&2; exit 1; }
codesign -d --entitlements - "$APP" 2>/dev/null | grep -q app-sandbox \
  || { echo "build/Glassine.app is not the sandboxed flavor. Run ./build.sh --appstore." >&2; exit 1; }
if pgrep -f "$BIN" >/dev/null; then
  echo "The sandboxed build is already running. Quit it first." >&2
  exit 1
fi
if [[ "$(defaults read com.apple.WindowManager GloballyEnabled 2>/dev/null)" == "1" ]]; then
  echo "* Stage Manager is on. The app brings itself to the front, so this usually still works;" >&2
  echo "  if a picture comes out as a thumbnail, turn it off in Control Centre and run again." >&2
fi

# --- Showcase library ---------------------------------------------------------------------------
BACKUP="$(mktemp -d /tmp/glassine-container.XXXXXX)"
restore() {
  pkill -f "$BIN" 2>/dev/null || true
  rm -rf "$DOCS"
  [[ -d "$BACKUP/Documents" ]] && mv "$BACKUP/Documents" "$DOCS"
  [[ -f "$BACKUP/prefs.plist" ]] && defaults import "$PREFS" "$BACKUP/prefs.plist" 2>/dev/null
  rm -rf "$BACKUP" "$SHOTS"
  echo "* Container restored"
}
trap restore EXIT

[[ -d "$DOCS" ]] && mv "$DOCS" "$BACKUP/Documents"
defaults export "$PREFS" "$BACKUP/prefs.plist" 2>/dev/null || true   # the window frame gets saved; put it back
mkdir -p "$DOCS"
cp -R "$LIB"/Essays "$LIB"/Notes "$LIB"/Ideas "$DOCS"/
# Daily notes are stored by how many days ago they are; give each its real date.
mkdir -p "$DOCS/Daily"
for f in "$LIB"/Daily/*.md; do
  ago=$(basename "$f" .md)
  title=$(date -v-"${ago}"d "+%A, %B %e, %Y" | sed 's/  */ /g')
  sed "s/{{DATE}}/$title/" "$f" > "$DOCS/Daily/$title.md"
  touch -t "$(date -v-"${ago}"d "+%Y%m%d1400")" "$DOCS/Daily/$title.md"
done
# Modified order decides how All Documents lays the cards out.
i=0
for rel in "Ideas/Names for the Boat.md" "Notes/Reading List.md" "Ideas/Small Rituals.md" \
           "Ideas/A Letter to September.md" "Notes/Launch Checklist.md" "Essays/On Writing Slowly.md"; do
  touch -t "$(date -v-$((6 - i))H "+%Y%m%d%H%M")" "$DOCS/$rel"; i=$((i + 1))
done
xattr -cr "$DOCS" 2>/dev/null || true
mkdir -p "$OUT" "$SHOTS"
: > "$OUT/log.txt"

# Where a phrase starts in a document, counted the way the editor counts
# (UTF-16 units), for parking the caret. Pure Swift, so nothing to install.
offset_of() {
  swift - "$1" "$2" 2>/dev/null <<'SWIFT'
import Foundation
let text = (try? String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)) ?? ""
if let r = text.range(of: CommandLine.arguments[2]) {
    print(text.utf16.distance(from: text.utf16.startIndex, to: r.lowerBound.samePosition(in: text.utf16)!))
} else { print(0) }
SWIFT
}

# --- One picture ----------------------------------------------------------------------------------
# shot <name> <settings json> [view: review|daily|-] [caret offset] [seconds to settle]
shot() {
  local name=$1 json=$2 view=${3:-} caret=${4:-} settle=${5:-3}
  [[ -n "${ONLY:-}" && "$ONLY" != "$name" ]] && return 0        # ONLY=2-focus ./screenshots.sh
  # shootCapture: the full composite with the backdrop, for the real glass. macOS calls it screen recording and says so.
  local args=(-glassine.shoot "$name.png" -glassine.launchWindow "$WINDOW" -glassine.shootDelay "$settle" -glassine.shootCapture 1
              -glassine.launchSettings "$(printf '%s' "$json" | base64 | tr -d '\n')")
  [[ -n "$view" && "$view" != "-" ]] && args+=(-glassine.launchView "$view")
  [[ -n "$caret" ]] && args+=(-glassine.launchCaret "$caret")
  rm -f "$SHOTS/$name.png" "$SHOTS/$name.png.status"
  open -n "$APP" --args "${args[@]}"
  local waited=0
  until [[ -f "$SHOTS/$name.png.status" ]]; do
    sleep 0.5; waited=$((waited + 1))
    if (( waited > 120 )); then echo "$name: the app never reported back." >&2; exit 1; fi
  done
  local status; status=$(cat "$SHOTS/$name.png.status")
  # Whatever the app noted on the way (the web view's loading, for one) goes
  # with the pictures, so a wrong one can be explained after the fact.
  if [[ -f "$SHOTS/log.txt" ]]; then { echo "== $name"; cat "$SHOTS/log.txt"; } >> "$OUT/log.txt"; rm -f "$SHOTS/log.txt"; fi
  if [[ "$status" != "ok" ]]; then echo "$name: $status" >&2; exit 1; fi
  # Let the app finish quitting before the next launch.
  while pgrep -f "$BIN" >/dev/null; do sleep 0.25; done
  mv "$SHOTS/$name.png" "$OUT/$name.png"
  echo "* $name.png  $(sips -g pixelWidth -g pixelHeight "$OUT/$name.png" | awk '/pixel/ {printf "%s ", $2}')"
}

# One key each: the decoder keeps the first of any duplicate, so anything a shot
# wants to vary is left out of the base and named by every shot.
base='"fontSize":19,"columnWidth":720,"sidebarVisible":true,"sidebarWidth":270,"expandedFolders":["Essays","Notes","Ideas","Daily"],"starred":["Essays/On Writing Slowly.md","Notes/Launch Checklist.md"],"reviewStyle":"glass","showCounter":true,"appearanceMode":"fixed"'
plain='"typewriterMode":false,"focusMode":false'

ESSAY="$DOCS/Essays/On Writing Slowly.md"
TOP=$(offset_of "$ESSAY" "Most tools for writing")          # end of the opening paragraph
MID=$(offset_of "$ESSAY" "A slow writer reads")             # the paragraph focus mode lights

shot 1-editor   '{'"$base"','"$plain"',"themeID":"dusk","lastOpenedDocument":"Essays/On Writing Slowly.md"}' - "$TOP"
shot 2-focus    '{'"$base"',"typewriterMode":true,"focusMode":true,"focusDimming":0.35,"themeID":"dusk","lastOpenedDocument":"Essays/On Writing Slowly.md"}' - "$MID"
shot 3-review   '{'"$base"','"$plain"',"themeID":"dusk","lastOpenedDocument":"Essays/On Writing Slowly.md"}' review "" 8
shot 4-library  '{'"$base"','"$plain"',"themeID":"dusk","lastOpenedDocument":null}'
shot 5-daily    '{'"$base"','"$plain"',"themeID":"dusk","lastOpenedDocument":"Essays/On Writing Slowly.md"}' daily
shot 6-light    '{'"$base"','"$plain"',"themeID":"paper","lastOpenedDocument":"Notes/Launch Checklist.md"}'

echo "* Done: six pictures in $OUT"
open "$OUT"
