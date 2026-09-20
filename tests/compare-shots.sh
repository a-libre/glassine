#!/usr/bin/env bash
# The same self-shots from two or three builds, for a pixel comparison — the
# check that a change meant to move nothing on the Mac moved nothing:
#   tests/compare-shots.sh   → dist/preview/cmp/{before,main,after}-<case>.png, build/compare-shots.log
# "after" is build/Glassine.app (./build.sh of the working tree). "main" is
# build/Glassine-main.app: main's code built the same way (a worktree, ./build.sh,
# copied out) — the fair baseline. "before" is build/Glassine-before.app, any
# released build kept aside. Missing apps are skipped; APPS="main after" and
# ONLY="review settings-type" narrow the run. Still pictures: the backdrop
# does not drift, the caret does not blink or play. Plain shots, launched in
# the background: they never take the keyboard.
#
# Known: Review's page comes out blank in these shots from an ad-hoc-signed
# build (main's and the branch's alike); the Developer ID build shows it. The
# settings-caret case differs run to run (its specimen caret is moving).
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin
LOG=build/compare-shots.log; : > "$LOG"
LIB=/tmp/glassine-shot-library-cmp
T="$(getconf DARWIN_USER_TEMP_DIR)glassine-shots"
OUT=dist/preview/cmp; mkdir -p "$OUT" "$T"
rm -rf "$LIB"; mkdir -p "$LIB/Essays"
cat > "$LIB/Formatting.md" <<'DOC'
# The quiet parts

Everything on this page is **plain Markdown**, styled *lightly*, ***both at once*** and ~~never~~ rarely in the way. A word like ==Glassine== gets a capsule of its own, the way a date does: @September 6, 2026.

## What the bar knows

- Bullets, drawn as bullets
    - nested ones too
1. A numbered list
- [ ] A task, with its box
- [x] One that is done

> A quote steps in from the margin and keeps its colour.

Inline `code` sits in a box; a [link](https://glassine.ink) keeps only its words. Then a rule:

---

### A third heading

The paragraph with the caret shows its marks, so it can be edited as written. #draft
DOC
printf '# An essay\n\nSomething longer, in a folder. #ideas\n' > "$LIB/Essays/An essay.md"
shoot() { # shoot <app> <prefix> <name> <theme> <hide> <extra-json> [args…]
  local app=$1 prefix=$2 name=$3 theme=$4 hide=$5 extra=$6; shift 6
  local file="$prefix-$name.png"
  rm -f "$T/$file" "$T/$file.status"
  pkill -f "$app/Contents/MacOS/Glassine" 2>/dev/null || true
  local json='{'"$extra"'"fontSize":17,"columnWidth":680,"sidebarVisible":true,"typewriterMode":false,"focusMode":false,"themeID":"'"$theme"'","appearanceMode":"fixed","showCounter":true,"backdropDrift":false,"caretBlink":"none","caretTricks":false,"hideSyntax":'"$hide"',"libraryPath":"'"$LIB"'","lastOpenedDocument":"Formatting.md"}'
  local b64; b64=$(printf '%s' "$json" | base64 | tr -d '\n')
  open -n -g "$app" --args -glassine.shoot "$file" -glassine.launchWindow 1200x860 -glassine.shootDelay 4 -glassine.launchCaret 40 -glassine.launchSettings "$b64" "$@"
  local w=0; until [[ -f "$T/$file.status" ]]; do sleep 0.5; w=$((w+1)); (( w > 60 )) && { echo "$file: no status" >> "$LOG"; return 1; }; done
  echo "$file: $(cat "$T/$file.status")" >> "$LOG"
  cp "$T/$file" "$OUT/$file"
}
want() { [[ -z "${ONLY:-}" || " $ONLY " == *" $1 "* ]]; }
for pair in "build/Glassine-before.app before" "build/Glassine-main.app main" "build/Glassine.app after"; do
  set -- $pair; app="$PWD/$1"; p=$2
  [[ -d "$app" ]] || continue
  [[ -z "${APPS:-}" || " $APPS " == *" $p "* ]] || continue
  want editor-shown && shoot "$app" "$p" editor-shown dusk false ''
  want editor-hidden && shoot "$app" "$p" editor-hidden dusk true ''
  want editor-light && shoot "$app" "$p" editor-light paper false ''
  want editor-desktop && shoot "$app" "$p" editor-desktop dusk false '"backdrop":"desktop",'
  want review && shoot "$app" "$p" review dusk false '' -glassine.launchView review -glassine.shootDelay 7
  want review-bookdark && shoot "$app" "$p" review-bookdark dusk false '"reviewStyle":"bookDark",' -glassine.launchView review -glassine.shootDelay 7
  for sec in library type caret theme backdrop about; do
    want "settings-$sec" && shoot "$app" "$p" "settings-$sec" dusk true '' -glassine.launchView "settings:$sec"
  done
done
pkill -f "$PWD/build/Glassine-before.app/Contents/MacOS/Glassine" 2>/dev/null || true
pkill -f "$PWD/build/Glassine-main.app/Contents/MacOS/Glassine" 2>/dev/null || true
pkill -f "$PWD/build/Glassine.app/Contents/MacOS/Glassine" 2>/dev/null || true
echo "all done" >> "$LOG"
