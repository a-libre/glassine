#!/usr/bin/env bash
# App Store screenshots, taken from the sandboxed build on the Mac's own screen.
#
#   ./build.sh --appstore && docs/appstore/screenshots.sh
#
# The app's sandbox container is backed up, filled with the showcase library in
# docs/appstore/library, photographed, and put back the way it was. Each shot is
# a fresh launch with the settings it needs written beforehand; Review and the
# Daily view are asked for by launch argument. Output: dist/screenshots/*.png at 2880×1800,
# which is one of the four sizes App Store Connect accepts for macOS.
#
# Run this from Terminal: macOS grants screen capture per app, and Terminal will
# ask for Screen & System Audio Recording the first time. Allow it and run again.
set -euo pipefail
cd "$(dirname "$0")/../.."

APP="$PWD/build/Glassine.app"
BIN="$APP/Contents/MacOS/Glassine"
LIB="$PWD/docs/appstore/library"
CONTAINER="$HOME/Library/Containers/com.alexlibre.glassine/Data"
DOCS="$CONTAINER/Documents"
PREFS="$CONTAINER/Library/Preferences/com.alexlibre.glassine"   # a defaults domain given by path
OUT="$PWD/dist/screenshots"
TARGET_W=2880
TARGET_H=1800

[[ -x "$BIN" ]] || { echo "No sandboxed build. Run ./build.sh --appstore first." >&2; exit 1; }
codesign -d --entitlements - "$APP" 2>/dev/null | grep -q app-sandbox \
  || { echo "build/Glassine.app is not the sandboxed flavor. Run ./build.sh --appstore." >&2; exit 1; }
if pgrep -f "$BIN" >/dev/null; then
  echo "The sandboxed build is already running. Quit it first." >&2
  exit 1
fi

# The finished files are squared up with Pillow: python3 -m pip install --user pillow
python3 -c 'import PIL' 2>/dev/null \
  || { echo "Python needs Pillow for the last step: python3 -m pip install --user pillow" >&2; exit 1; }

# Stage Manager parks the window of whatever app is not on the current stage as a
# thumbnail at the edge of the screen, which is no use to photograph and is the
# hardest failure here to recognise from a log.
if [[ "$(defaults read com.apple.WindowManager GloballyEnabled 2>/dev/null)" == "1" ]]; then
  echo "Stage Manager is on, and it shrinks the window this script needs to photograph." >&2
  echo "Turn it off in Control Centre (menu bar, top right), run this, turn it back on." >&2
  exit 1
fi

# Screen capture is a permission, and the failure is silent enough to waste an
# entire run, so ask for eight pixels before touching anything.
if ! screencapture -x -R 0,0,8,8 /tmp/glassine-capture-test.png 2>/dev/null \
   || [[ ! -s /tmp/glassine-capture-test.png ]]; then
  rm -f /tmp/glassine-capture-test.png
  echo "This program cannot capture the screen." >&2
  echo "Open System Settings > Privacy & Security > Screen & System Audio Recording," >&2
  echo "turn it on for Terminal, and run this again." >&2
  exit 1
fi
rm -f /tmp/glassine-capture-test.png

# --- Window finder ----------------------------------------------------------------------------
# Two things the shell cannot answer: the size of the screen a window may use, and
# where a running app's window actually is. Both come from the window server, so
# neither needs Accessibility.
HELPER=/tmp/glassine-winbounds
cat > /tmp/glassine-winbounds.swift <<'SWIFT'
import AppKit

if CommandLine.arguments[1] == "screen" {
    // The area a window may occupy, in Cocoa coordinates: what AppKit records
    // alongside a saved window frame, and what the frame must be centred in.
    let f = NSScreen.main!.visibleFrame
    print("\(Int(f.origin.x)) \(Int(f.origin.y)) \(Int(f.width)) \(Int(f.height)) \(Int(NSScreen.main!.backingScaleFactor))")
    exit(0)
}

// The app's largest ordinary window, in screen pixels with the origin at the top
// left — which is the rectangle screencapture -R wants. Small windows (a panel
// mid-animation, an off-screen placeholder) are skipped by taking the largest.
let pid = Int32(CommandLine.arguments[1])!
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as! [[String: Any]]
var best: (w: Int, h: Int, x: Int, y: Int)?
for win in list where (win[kCGWindowOwnerPID as String] as? Int32) == pid
                   && (win[kCGWindowLayer as String] as? Int) == 0 {
    let b = win[kCGWindowBounds as String] as! [String: CGFloat]
    let candidate = (w: Int(b["Width"]!), h: Int(b["Height"]!), x: Int(b["X"]!), y: Int(b["Y"]!))
    if best == nil || candidate.w * candidate.h > best!.w * best!.h { best = candidate }
}
if let b = best { print("\(b.x) \(b.y) \(b.w) \(b.h)") }
SWIFT
swiftc -O /tmp/glassine-winbounds.swift -o "$HELPER" 2>&1 | grep -v warning || true
[[ -x "$HELPER" ]] || { echo "Could not build the window helper." >&2; exit 1; }

# --- Screen geometry ------------------------------------------------------------------------
# screencapture renders a region at the display's backing scale — 2 on any Retina
# Mac, whatever "More Space" setting is in use — so a 1440×900-point window comes
# out as exactly 2880×1800 pixels, with nothing to crop or resample.
read -r sc_x sc_y sc_w sc_h scale < <("$HELPER" screen)
[[ -n "${scale:-}" ]] || { echo "Could not read the display geometry." >&2; exit 1; }
win_w=$(( TARGET_W / scale ))
win_h=$(( TARGET_H / scale ))
if (( win_w > sc_w || win_h > sc_h )); then
  echo "The usable screen (${sc_w}x${sc_h} points) is too small for a ${win_w}x${win_h} window." >&2
  echo "Lower TARGET_W/TARGET_H to 2560x1600 and run this again." >&2
  exit 1
fi
win_x=$(( sc_x + (sc_w - win_w) / 2 ))
win_y=$(( sc_y + (sc_h - win_h) / 2 ))
# The format AppKit saves: the window's frame, then the screen area it belongs to.
FRAME="$win_x $win_y $win_w $win_h $sc_x $sc_y $sc_w $sc_h "
echo "* Screen ${sc_w}x${sc_h} pt at ${scale}x; window ${win_w}x${win_h} pt -> ${TARGET_W}x${TARGET_H} px"

# --- Showcase library ---------------------------------------------------------------------------
BACKUP="$(mktemp -d /tmp/glassine-container.XXXXXX)"
restore() {
  pkill -f "$BIN" 2>/dev/null || true
  rm -rf "$DOCS"
  [[ -d "$BACKUP/Documents" ]] && mv "$BACKUP/Documents" "$DOCS"
  [[ -f "$BACKUP/prefs.plist" ]] && defaults import "$PREFS" "$BACKUP/prefs.plist"
  rm -rf "$BACKUP"
  echo "* Container restored"
}
trap restore EXIT

[[ -d "$DOCS" ]] && mv "$DOCS" "$BACKUP/Documents"
defaults export "$PREFS" "$BACKUP/prefs.plist" 2>/dev/null || true
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
mkdir -p "$OUT"

# Offset of a phrase in a document, for parking the caret.
offset_of() { python3 - "$1" "$2" <<'PY'
import sys; text = open(sys.argv[1], encoding="utf-8").read(); i = text.find(sys.argv[2]); print(i if i >= 0 else 0)
PY
}
ESSAY="$DOCS/Essays/On Writing Slowly.md"
MID=$(offset_of "$ESSAY" "A slow writer reads")

# Preferences are held by cfprefsd, which flushes an app's cached values a moment
# after it exits — long enough to overwrite a write made right after a kill. So
# wait for the process to be gone before writing, and check the write landed.
quit_app() {
  local pid=$1
  kill "$pid" 2>/dev/null || true
  for _ in $(seq 1 40); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.25
  done
  sleep 1.5
}

write_prefs() {
  local json=$1 got=""
  for _ in $(seq 1 6); do
    defaults write "$PREFS" glassine.settings.v1 -data "$(printf '%s' "$json" | xxd -p | tr -d '\n')"
    defaults write "$PREFS" "NSWindow Frame GlassineMainWindow" -string "$FRAME"
    got=$(defaults read "$PREFS" "NSWindow Frame GlassineMainWindow" 2>/dev/null || true)
    # $(echo $x) unquoted collapses runs of spaces and trims the ends, which is
    # the only difference between what AppKit stores and what defaults prints.
    [[ "$(echo $got)" == "$(echo $FRAME)" ]] && return 0
    sleep 1
  done
  echo "The window frame will not stay written (it reads back as '$got')." >&2
  echo "Quit Glassine everywhere, then run this again." >&2
  exit 1
}

# --- One shot -------------------------------------------------------------------------------------
# shot <name> <settings json> [launch view: review|daily]
shot() {
  local name=$1 json=$2 view=${3:-}
  write_prefs "$json"
  if [[ -n "$view" ]]; then open -n "$APP" --args -glassine.launchView "$view"; else open -n "$APP"; fi
  local pid="" bounds="" w=0
  for i in $(seq 1 60); do
    sleep 0.5
    pid=$(pgrep -n -f "$BIN" || true)
    [[ -z "$pid" ]] && continue
    bounds=$("$HELPER" "$pid" || true)
    [[ -z "$bounds" ]] && continue
    w=$(awk '{print $3}' <<<"$bounds")
    (( w >= win_w - 4 )) && break
    # Under Stage Manager an app that is not the active one is parked in the
    # strip as a thumbnail, which is what a tiny window means. Activating it
    # brings it back to full size; `open` on a running app does that without
    # needing permission to send Apple events.
    (( i % 6 == 0 )) && open "$APP"
  done
  if (( w < win_w - 4 )); then
    echo "The window came up as '${bounds:-nothing}', not ${win_w} points wide." >&2
    echo "If Stage Manager is on, turn it off in Control Centre and run this again." >&2
    exit 1
  fi
  sleep 3                                     # library scan, first layout, caret settle
  read -r x y _ h <<<"$bounds"
  screencapture -x -R "$x,$y,$win_w,$h" "$OUT/$name.png"
  quit_app "$pid"
  # App Store Connect refuses an alpha channel, and screencapture writes one.
  # Flatten it; trim a rounding pixel if the size is off by a hair, scale if by more.
  python3 - "$OUT/$name.png" "$TARGET_W" "$TARGET_H" <<'PYEOF'
import sys
from PIL import Image
path, W, H = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
im = Image.open(path).convert("RGB")
if im.size != (W, H):
    if im.width < W or im.height < H:
        sys.exit(f"{path}: captured {im.width}x{im.height}, smaller than {W}x{H}")
    if im.width - W <= 4 and im.height - H <= 4:
        left, top = (im.width - W) // 2, (im.height - H) // 2
        im = im.crop((left, top, left + W, top + H))
    else:
        im = im.resize((W, H), Image.LANCZOS)
im.save(path, optimize=True)
print(f"* {path.rsplit('/', 1)[-1]}  {im.width}x{im.height}")
PYEOF
}

base='"fontSize":19,"columnWidth":720,"sidebarVisible":true,"sidebarWidth":270,"expandedFolders":["Essays","Notes","Ideas","Daily"],"starred":["Essays/On Writing Slowly.md","Notes/Launch Checklist.md"],"typewriterMode":false,"focusMode":false,"reviewStyle":"glass","showCounter":true,"appearanceMode":"fixed"'

shot 1-editor   '{'"$base"',"themeID":"ocean","lastOpenedDocument":"Essays/On Writing Slowly.md","caretPositions":{"Essays/On Writing Slowly.md":0}}'
shot 2-focus    '{'"$base"',"themeID":"ocean","typewriterMode":true,"focusMode":true,"lastOpenedDocument":"Essays/On Writing Slowly.md","caretPositions":{"Essays/On Writing Slowly.md":'"$MID"'}}'
shot 3-review   '{'"$base"',"themeID":"ocean","lastOpenedDocument":"Essays/On Writing Slowly.md"}' review
shot 4-library  '{'"$base"',"themeID":"ocean","lastOpenedDocument":null}'
shot 5-daily    '{'"$base"',"themeID":"ocean","lastOpenedDocument":"Essays/On Writing Slowly.md"}' daily
shot 6-light    '{'"$base"',"themeID":"paper","lastOpenedDocument":"Notes/Launch Checklist.md","caretPositions":{"Notes/Launch Checklist.md":0}}'

echo "* Done: six shots in $OUT"
open "$OUT"
