#!/usr/bin/env bash
# Review self-shots from the direct build: one document in every Review style,
# on a temp library, in the dusk and paper themes, and a contact sheet of them.
# tests/shot-review.sh [all|<style>|sheet] → dist/preview/review-<theme>-<style>.jpg,
# dist/preview/review-sheet-<theme>.jpg
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/build/Glassine.app"
LIB=/tmp/glassine-shot-library-review
T="$(getconf DARWIN_USER_TEMP_DIR)glassine-shots"
pkill -f "$APP/Contents/MacOS/Glassine" 2>/dev/null || true
rm -rf "$LIB"; mkdir -p "$LIB"
cat > "$LIB/The Lamp.md" <<'DOC'
# The Lamp at the End of the Pier

The lamp was lit every evening by a man nobody had met. He came at dusk, went up the iron stair, and by the time the last of the light had gone from the water the lamp was burning and he was not there. This went on for eleven years.

Nobody thought to ask who paid him. The harbour board had a line for it, and the line was paid, and that was the whole of the arrangement as far as anyone could tell. *A lamp that lights itself,* the fishermen said, and left it there.

## What the ledger said

The ledger said nothing. It said **oil, wick, glass** in a hand that did not change, and it said them for eleven years, and then it stopped.

- The oil was ordered from Lowestoft.
- The wick from a chandler in the town.
- The glass was never replaced, which was the strange part.

> There is a kind of care that leaves no mark, and it is the only kind that lasts.

1. Go up the stair at dusk.
2. Light the lamp.
3. Come down before the dark.

- [x] Ask the harbour board
- [ ] Find the chandler

---

What follows is the part of the story nobody tells, because it is not a story, only a list of evenings. Here is a line of `code`, and a [link](https://glassine.ink) to somewhere else, and a date: @September 26, 2026.

| Year | Evenings | Missed |
|---|---|---|
| 1911 | 365 | 0 |
| 1912 | 366 | 0 |
| 1921 | 12 | — |

```
lamp.light(at: dusk)
```

She kept the last of the oil in a jar on the sill,
and the jar in the window, and the window to the sea,
and the sea did what it does.

The stanza after this one is a stanza.
DOC
mkdir -p "$T"; : > "$T/log.txt"
STYLES="glass reader gallery editorial newspaper book bookDark typewriter notebook thesis verse github mono blueprint"

shoot() {
  local theme=$1 style=$2
  local name="review-$theme-$style"
  rm -f "$T/$name.png" "$T/$name.png.status"
  local json='{"reviewStyle":"'"$style"'","fontSize":17,"columnWidth":680,"sidebarVisible":false,"typewriterMode":false,"focusMode":false,"themeID":"'"$theme"'","appearanceMode":"fixed","showCounter":true,"hideSyntax":true,"centerHeadings":false,"libraryPath":"'"$LIB"'","lastOpenedDocument":"The Lamp.md"}'
  local b64; b64=$(printf '%s' "$json" | base64 | tr -d '\n')
  open -n "$APP" --args -glassine.shoot "$name.png" -glassine.launchWindow 1200x860 -glassine.shootDelay 5 -glassine.launchCaret 0 -glassine.launchView review -glassine.launchSettings "$b64"
  local w=0; until [[ -f "$T/$name.png.status" ]]; do sleep 0.5; w=$((w+1)); (( w > 60 )) && { echo "no status for $name"; return 1; }; done
  printf '%s: ' "$name"; cat "$T/$name.png.status"; echo
  mkdir -p dist/preview
  sips -z 860 1200 -s format jpeg "$T/$name.png" --out "dist/preview/$name.jpg" >/dev/null
}

sheet() {
  local theme=$1
  python3 - "$theme" $STYLES <<'PY'
import sys
from PIL import Image
theme, styles = sys.argv[1], sys.argv[2:]
cols, w, h = 4, 600, 430
rows = (len(styles) + cols - 1) // cols
out = Image.new('RGB', (cols * w, rows * h), (20, 20, 20))
for i, s in enumerate(styles):
    try:
        im = Image.open(f'dist/preview/review-{theme}-{s}.jpg').resize((w, h))
    except Exception:
        continue
    out.paste(im, ((i % cols) * w, (i // cols) * h))
out.save(f'dist/preview/review-sheet-{theme}.jpg', quality=82)
print(f'dist/preview/review-sheet-{theme}.jpg')
PY
}

case "${1:-all}" in
  all) for th in dusk paper; do for s in $STYLES; do shoot $th $s; done; sheet $th; done ;;
  sheet) for th in dusk paper; do sheet $th; done ;;
  *) for th in ${2:-dusk}; do shoot $th "$1"; done ;;
esac
