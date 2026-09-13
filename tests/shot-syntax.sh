#!/usr/bin/env bash
# Editor self-shots from the direct build: the same document with the Markdown
# shown and hidden, on a temp library. ./build/shot-syntax.sh → dist/preview/syntax-{shown,hidden}.jpg
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/build/Glassine.app"
LIB=/tmp/glassine-shot-library-syntax
T="$(getconf DARWIN_USER_TEMP_DIR)glassine-shots"
pkill -f "$APP/Contents/MacOS/Glassine" 2>/dev/null || true
rm -rf "$LIB"; mkdir -p "$LIB"
cat > "$LIB/Formatting.md" <<'DOC'
# The quiet parts

Everything on this page is **plain Markdown**, styled *lightly* and ~~never~~ rarely in the way. A word like ==Glassine== gets a capsule of its own, the way a date does: @September 6, 2026.

## What the bar knows

- Bullets, drawn as bullets
- Nested ones too
    - like this one
1. A numbered list
2. keeps its numbers
- [ ] A task, with its box
- [x] One that is done

> A quote steps in from the margin and keeps its colour.

Inline `code` sits in a box; a [link](https://glassine.ink) keeps only its words. Then a rule:

---

The paragraph with the caret shows its marks, so it can be edited as written.
DOC
printf '# Rule\n\nBefore the rule, a line of text.\n\n---\n\nAfter the rule, another line.\n' > "$LIB/Rule.md"
mkdir -p "$T"; : > "$T/log.txt"
shoot() {
  local name=$1 hide=$2 caret=$3; shift 3
  rm -f "$T/$name.png" "$T/$name.png.status"
  local json='{'"${EXTRA_JSON:-}"'"fontSize":17,"columnWidth":680,"sidebarVisible":false,"typewriterMode":false,"focusMode":false,"themeID":"'"${THEME:-dusk}"'","appearanceMode":"fixed","showCounter":true,"hideSyntax":'"$hide"',"libraryPath":"'"$LIB"'","lastOpenedDocument":"'"${DOC:-Formatting.md}"'"}'
  local b64; b64=$(printf '%s' "$json" | base64 | tr -d '\n')
  open -n "$APP" --args -glassine.shoot "$name.png" -glassine.launchWindow 1200x860 -glassine.shootDelay 4 -glassine.launchCaret "$caret" -glassine.launchSettings "$b64" "$@"
  local w=0; until [[ -f "$T/$name.png.status" ]]; do sleep 0.5; w=$((w+1)); (( w > 60 )) && { echo "no status"; return 1; }; done
  cat "$T/$name.png.status"; echo
  mkdir -p dist/preview
  sips -z 860 1200 -s format jpeg "$T/$name.png" --out "dist/preview/$name.jpg" >/dev/null
}
case "${1:-all}" in
  all) shoot syntax-shown false 40; shoot syntax-hidden true 40 ;;
  bar) shoot syntax-bar true 40 -glassine.shootSelect 19,30 ;;
  slash) shoot syntax-slash true 999999 -glassine.shootSlash 1 ;;
  rule) shoot syntax-rule false 999999 ;;
  ruleplain) DOC=Rule.md shoot syntax-rule-plain true 13 -glassine.shootSelect 13,0 ;;
  rulebounce) DOC=Rule.md shoot syntax-rule-bounce true 13 -glassine.shootSelect 13,0 -glassine.shootBounce review -glassine.shootDelay 5 ;;
  ruleleave) DOC=Rule.md shoot syntax-rule-leave true 43 -glassine.shootSelect 43,0 -glassine.shootSelectThen 13,0 -glassine.shootDelay 5 ;;
  ruleleave2) DOC=Rule.md shoot syntax-rule-leave2 true 43 -glassine.shootSelect 43,0 -glassine.shootSelectThen 50,0 -glassine.shootDelay 5 ;;
  ruleon) DOC=Rule.md shoot syntax-rule-on true 43 -glassine.shootSelect 43,0 ;;
  indent) EXTRA_JSON='"paragraphIndent":1.5,' shoot syntax-indent false 40 ;;
  narrow) EXTRA_JSON='"columnWidth":150,' shoot syntax-narrow true 0 ;;
  edit) EXTRA_JSON='"columnWidth":150,' shoot syntax-edit true 188 -glassine.shootSlash 1 ;;
  bookdark) EXTRA_JSON='"reviewStyle":"bookDark",' shoot syntax-bookdark false 0 -glassine.launchView review -glassine.shootDelay 7 ;;
  carets) for sh in bar pin serif wedge ghost comet glow hollow; do EXTRA_JSON='"caretShape":"'$sh'","caretBlink":"none","caretWidth":4,' shoot "syntax-caret-$sh" false 40 -glassine.shootSelect 40,0; done ;;
  caret) sh=$2; EXTRA_JSON='"caretShape":"'$sh'","caretBlink":"none","caretWidth":4,' shoot "syntax-caret-$sh" false 40 -glassine.shootSelect 40,0 ;;
  settings) sec=${2:-type}; EXTRA_JSON='"sidebarVisible":true,' shoot "syntax-settings-$sec" true 40 -glassine.launchView "settings:$sec" ;;
  settingslight) sec=${2:-type}; THEME=paper EXTRA_JSON='"sidebarVisible":true,' shoot "syntax-settings-light-$sec" true 40 -glassine.launchView "settings:$sec" ;;
  settingsfind) q=${2:-blink}; EXTRA_JSON='"sidebarVisible":true,' shoot "syntax-settings-find-$q" true 40 -glassine.launchView settings:library -glassine.settingsQuery "$q" ;;
  syncpanel) EXTRA_JSON='"sidebarVisible":true,' shoot syntax-settings-sync true 40 -glassine.launchView settings:library ;;
  syncconnected) rm -rf /tmp/glassine-syncdemo; mkdir -p /tmp/glassine-syncdemo; EXTRA_JSON='"sidebarVisible":true,' shoot syntax-settings-sync-connected true 40 -glassine.launchView settings:library -glassine.syncDemo /tmp/glassine-syncdemo -glassine.shootDelay 6 ;;
  settingsall) for sec in library type caret modes typing theme backdrop about; do EXTRA_JSON='"sidebarVisible":true,' shoot "syntax-settings-$sec" true 40 -glassine.launchView "settings:$sec"; done ;;
  trick) tr=$2; at=${3:-3.6}; EXTRA_JSON='"caretShape":"bar","caretBlink":"none","caretWidth":4,' shoot "syntax-trick-$tr" false 40 -glassine.shootSelect 40,0 -glassine.trickAfter 4 -glassine.trick "$tr" -glassine.shootDelay "$at" ;;
  undo) nm=${2:-undo}; EXTRA_JSON='"sidebarVisible":true,' shoot "syntax-$nm" true 40 -glassine.shootSelect 40,0 -glassine.shootDelay 10 ;;
  backdroplight) sh=$2; THEME=paper EXTRA_JSON='"backdrop":"'$sh'","backdropDrift":false,"backdropFrost":0.3,"sidebarVisible":true,' shoot "syntax-backdrop-light-$sh" true 40 ;;
  backdrops-pane) EXTRA_JSON='"backdrop":"dusk","sidebarVisible":true,' shoot syntax-backdrops-pane true 40 -glassine.launchView backdrops ;;
  frost) fr=$2; EXTRA_JSON='"backdrop":"nebula","backdropDrift":false,"backdropFrost":'$fr',"sidebarVisible":true,' shoot "syntax-frost-$fr" true 40 ;;
  loose) mkdir -p /tmp/glassine-elsewhere; printf '# A file from elsewhere\n\nOpened in place, from a folder that is not the library.\n' > /tmp/glassine-elsewhere/Elsewhere.md
    rm -f "$T/syntax-loose.png" "$T/syntax-loose.png.status"
    json='{"sidebarVisible":true,"fontSize":17,"columnWidth":680,"typewriterMode":false,"focusMode":false,"themeID":"dusk","appearanceMode":"fixed","showCounter":true,"hideSyntax":true,"libraryPath":"'"$LIB"'","lastOpenedDocument":"Formatting.md"}'
    b64=$(printf '%s' "$json" | base64 | tr -d '\n')
    open -n -a "$APP" /tmp/glassine-elsewhere/Elsewhere.md --args -glassine.shoot syntax-loose.png -glassine.launchWindow 1200x860 -glassine.shootDelay 5 -glassine.launchSettings "$b64"
    w=0; until [[ -f "$T/syntax-loose.png.status" ]]; do sleep 0.5; w=$((w+1)); (( w > 60 )) && { echo "no status"; exit 1; }; done
    cat "$T/syntax-loose.png.status"; echo; mkdir -p dist/preview; sips -z 860 1200 -s format jpeg "$T/syntax-loose.png" --out dist/preview/syntax-loose.jpg >/dev/null ;;
  backdrop) sh=$2; EXTRA_JSON='"backdrop":"'$sh'","backdropDrift":false,"backdropFrost":0.3,"sidebarVisible":true,' shoot "syntax-backdrop-$sh" true 40 ;;
esac
