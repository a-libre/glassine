#!/usr/bin/env bash
# Pictures on the page, from the direct build, on a temp library:
#   ./tests/shot-images.sh page      a page with a picture already linked, syntax shown
#   ./tests/shot-images.sh hidden    the same with the syntax hidden (the caption alone)
#   ./tests/shot-images.sh paste     a picture pasted into the page (clipboard set by pasteboard-image.swift)
#   ./tests/shot-images.sh tall      a tall picture pasted, for the height cap
#   ./tests/shot-images.sh first     a document that opens with its picture (the typesetter's case)
#   ./tests/shot-images.sh focus     focus mode, the caret in the paragraph above: the picture dimmed
#   ./tests/shot-images.sh wall      the card on the wall, with its thumbnail
#   ./tests/shot-images.sh review    the page in Review, the picture inside it
#   ./tests/shot-images.sh copy      Copy as Rich Text, then what the clipboard holds
#   ./tests/shot-images.sh all
# Pictures land in dist/preview/images-*.jpg; the paste cases print the document after.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/build/Glassine.app"
LIB=/tmp/glassine-shot-library-images
T="$(getconf DARWIN_USER_TEMP_DIR)glassine-shots"
pkill -f "$APP/Contents/MacOS/Glassine" 2>/dev/null || true
rm -rf "$LIB"; mkdir -p "$LIB/Essays" "$LIB/Images" "$T"
OUT="$LIB/Images/harbour.png" swift tests/pasteboard-image.swift >/dev/null
printf '# A walk to the harbour\n\nThe fog had not lifted by nine, and the boats sat in it like ideas.\n\n![The harbour, nine o'"'"'clock](../Images/harbour.png)\n\nBy eleven the sun had the masts, and the gulls had the rest.\n' > "$LIB/Essays/Harbour.md"
printf '# Paste here\n\nA line before the picture.\n\n' > "$LIB/Paste.md"
printf '# Garden\n\nTomatoes in, late.\n' > "$LIB/Garden.md"
printf '![](Images/harbour.png)\n\nA picture first, then the words — the first paragraph of a document has no line above it to make room under, so the typesetter makes it.\n' > "$LIB/First.md"

shoot() {
  local name=$1; shift
  rm -f "$T/$name.png" "$T/$name.png.status"
  local json='{'"${EXTRA_JSON:-}"'"fontSize":16,"sidebarVisible":true,"typewriterMode":false,"focusMode":'"${FOCUS:-false}"',"themeID":"'"${THEME:-midnight}"'","backdrop":"'"${BACKDROP:-softsky}"'","appearanceMode":"fixed","showCounter":true,"libraryPath":"'"$LIB"'","lastOpenedDocument":"'"${DOC:-Essays/Harbour.md}"'","tourSeen":true}'
  local b64; b64=$(printf '%s' "$json" | base64 | tr -d '\n')
  open -n "$APP" --args -glassine.shoot "$name.png" -glassine.launchWindow 1280x840 -glassine.shootDelay "${DELAY:-4}" -glassine.launchSettings "$b64" "$@"
  local w=0; until [[ -f "$T/$name.png.status" ]]; do sleep 0.5; w=$((w+1)); (( w > 80 )) && { echo "no status"; return 1; }; done
  cat "$T/$name.png.status"; echo
  mkdir -p dist/preview
  sips -z 840 1280 -s format jpeg "$T/$name.png" --out "dist/preview/$name.jpg" >/dev/null
}
case "${1:-all}" in
  page) shoot images-page ;;
  hidden) EXTRA_JSON='"hideSyntax":true,' shoot images-hidden -glassine.launchCaret 0 ;;
  paste) swift tests/pasteboard-image.swift >/dev/null; DOC=Paste.md DELAY=6 shoot images-paste -glassine.launchCaret 44 -glassine.shootScript "1.0:paste;2.0:type@40: and a line after it."; echo "--- Paste.md"; cat "$LIB/Paste.md"; ls "$LIB/Images" ;;
  tall) swift tests/pasteboard-image.swift tall >/dev/null; DOC=Paste.md DELAY=6 shoot images-tall -glassine.launchCaret 44 -glassine.shootScript "1.0:paste"; ls "$LIB/Images" ;;
  first) DOC=First.md shoot images-first -glassine.launchCaret 40 ;;
  focus) FOCUS=true shoot images-focus -glassine.launchCaret 20 ;;
  wall) DELAY=5 shoot images-wall -glassine.shootScript "0.5:gallery" ;;
  review) shoot images-review -glassine.launchView review ;;
  # Copy as Rich Text, then what the clipboard holds: the HTML should carry the
  # picture as a data URL, the RTFD as an attachment.
  copy) DELAY=3 shoot images-copy -glassine.shootScript "1.0:cmd:copy-rtf"
        printf 'import AppKit\nlet pb = NSPasteboard.general\nprint("types:", (pb.types ?? []).map(\\.rawValue).joined(separator: " "))\nif let h = pb.string(forType: .html) { print("html \\(h.utf8.count) bytes,", h.contains("<img src=\\"data:image/") ? "picture inline" : "NO INLINE PICTURE") }\nif let d = pb.data(forType: .rtfd) { print("rtfd \\(d.count) bytes") }\nif let d = pb.data(forType: .rtf) { print("rtf \\(d.count) bytes") }\n' | swift - 2>/dev/null ;;
  all) "$0" page; "$0" hidden; "$0" paste; "$0" tall; "$0" first; "$0" focus; "$0" wall; "$0" review; "$0" copy ;;
esac
