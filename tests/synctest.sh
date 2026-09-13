#!/usr/bin/env bash
# The merge, exercised with no network: two libraries take turns syncing
# through a folder that stands in for the repository (FolderRemote).
# ./build.sh && ./tests/synctest.sh → PASS/FAIL lines; the app's own log of
# each round is in /tmp/glassine-synctest/R/log.txt.
set -u
cd "$(dirname "$0")/.."
APP="$PWD/build/Glassine.app"
T=/tmp/glassine-synctest
rm -rf "$T"; mkdir -p "$T/A/Sub" "$T/B" "$T/R" "$T/C"
json='{"libraryPath":"'"$T/C"'","sidebarVisible":false}'
b64=$(printf '%s' "$json" | base64 | tr -d '\n')
run() {  # run <lib> [busy]
  local lib=$1; local busy=${2:-}
  local args=(-glassine.syncTest "$T/$lib" -glassine.syncFolder "$T/R" -glassine.launchSettings "$b64")
  [[ -n "$busy" ]] && args+=(-glassine.syncBusy "$busy")
  open -n -W "$APP" --args "${args[@]}"
  echo "[$lib] $(grep '^outcome' "$T/R/log.txt" | tail -1)"
}
fails=0
check() { # check <desc> <shell test>
  if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; fails=$((fails+1)); fi
}

printf 'one\n' > "$T/A/One.md"; printf 'two\n' > "$T/A/Sub/Two.md"
printf 'hidden\n' > "$T/A/.hidden.md"; printf 'pdf' > "$T/A/notes.pdf"
run A; run B
check "B got One and Sub/Two" '[[ "$(cat "$T/B/One.md")" == one && "$(cat "$T/B/Sub/Two.md")" == two ]]'
check "hidden and non-document files stay out" '! grep -q "hidden\|notes.pdf" "$T/R/head.json"'

printf 'one, edited on A\n' > "$T/A/One.md"; rm "$T/A/Sub/Two.md"; printf 'three\n' > "$T/B/Three.md"
run A; run B; run A
check "edit reached B" '[[ "$(cat "$T/B/One.md")" == "one, edited on A" ]]'
check "removal reached B" '[[ ! -e "$T/B/Sub/Two.md" ]]'
check "B's new file reached A" '[[ "$(cat "$T/A/Three.md")" == three ]]'

printf 'A version\n' > "$T/A/One.md"; printf 'B version\n' > "$T/B/One.md"
run A; run B; run A
check "conflict: B kept its own" '[[ "$(cat "$T/B/One.md")" == "B version" ]]'
check "conflict: A's version beside it on B" '[[ "$(cat "$T/B/One (conflict).md")" == "A version" ]]'
check "conflict: A now has B's version and the copy" '[[ "$(cat "$T/A/One.md")" == "B version" && "$(cat "$T/A/One (conflict).md")" == "A version" ]]'

mv "$T/A/Three.md" "$T/A/Four.md"
run A; run B
check "rename reached B" '[[ -e "$T/B/Four.md" && ! -e "$T/B/Three.md" ]]'

printf 'four, edited on B\n' > "$T/B/Four.md"
run B; run A Four.md
check "busy file deferred" '[[ "$(cat "$T/A/Four.md")" == three ]]'
run A
check "deferred file arrives once free" '[[ "$(cat "$T/A/Four.md")" == "four, edited on B" ]]'

run A; run B
check "quiet round" '[[ "$(grep "^outcome" "$T/R/log.txt" | tail -1)" == *"pulled=[] pushed=[] removedHere=[] removedThere=[] conflicts=[] deferred=[] error=none"* ]]'
echo "failures: $fails"
