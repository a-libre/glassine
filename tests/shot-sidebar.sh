#!/usr/bin/env bash
# Sidebar self-shots from the direct build, on a temp library with two months
# of daily notes of every length: the calendar, and a row carried through the
# tree (mid-drag and after the drop, and onto a folder).
#   tests/shot-sidebar.sh          → dist/preview/sidebar-{dusk,paper}.jpg
#   tests/shot-sidebar.sh drag     → dist/preview/sidebar-drag{,-dropped,-folder,-folder-dropped}.jpg
# The drag is synthetic (-glassine.shootDrag x,y,dx,dy, points from the
# window's top left): the events go to the window, the Mac's pointer stays.
# Look for "drag begin" / "drag end" in the run's log.txt.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/build/Glassine.app"
LIB=/tmp/glassine-shot-library-sidebar
T="$(getconf DARWIN_USER_TEMP_DIR)glassine-shots"
pkill -f "$APP/Contents/MacOS/Glassine" 2>/dev/null || true
rm -rf "$LIB"; mkdir -p "$LIB/Daily" "$LIB/Essays" "$LIB/Work"
python3 - "$LIB" <<'PY'
import sys, os, random, datetime
lib = sys.argv[1]
random.seed(4)
words = ("the quiet parts of the day are the ones worth writing down and the page is patient about it " * 40).split()
today = datetime.date.today()
for i in range(0, 60):
    d = today - datetime.timedelta(days=i)
    if random.random() < 0.25 and i > 0: continue
    n = 260 if i == 0 else random.choice([40, 80, 150, 220, 350, 500, 900, 1400])
    title = d.strftime("%A, %B %-d, %Y")
    open(os.path.join(lib, "Daily", title + ".md"), "w").write("# " + title + "\n\n" + " ".join(random.choices(words, k=n)) + "\n")
for folder, names in {"": ["Welcome", "Reading list", "Ideas for the porch"],
                      "Essays": ["On Writing", "The long way round", "Glass and paper"],
                      "Work": ["Q4 plan", "Interview loop", "Notes for Ethan"]}.items():
    for name in names:
        open(os.path.join(lib, folder, name + ".md"), "w").write("# " + name + "\n\nA few lines about " + name.lower() + ".\n")
PY
mkdir -p "$T"; : > "$T/log.txt"
shoot() {
  local name=$1; shift
  rm -f "$T/$name.png" "$T/$name.png.status" "$T/$name-dropped.png" "$T/$name-dropped.png.status"
  local json='{"fontSize":16,"columnWidth":660,"sidebarVisible":true,"sidebarWidth":250,"typewriterMode":false,"focusMode":false,"themeID":"'"${THEME:-dusk}"'","appearanceMode":"fixed","libraryPath":"'"$LIB"'","lastOpenedDocument":"Essays/On Writing.md","expandedFolders":["*documents","Essays","Work"]}'
  local b64; b64=$(printf '%s' "$json" | base64 | tr -d '\n')
  open -n "$APP" --args -glassine.shoot "$name.png" -glassine.launchWindow 1200x860 -glassine.shootDelay 4 -glassine.launchSettings "$b64" "$@"
  local w=0; until [[ -f "$T/$name.png.status" ]]; do sleep 0.5; w=$((w+1)); (( w > 60 )) && { echo "no status"; return 1; }; done
  cat "$T/$name.png.status"; echo
  sleep 2
  mkdir -p dist/preview
  for n in "$name" "$name-dropped"; do
    [[ -f "$T/$n.png" ]] && sips -Z 1000 -s format jpeg -s formatOptions 85 "$T/$n.png" --out "dist/preview/$n.jpg" >/dev/null
  done
  ls dist/preview | grep "$name"
}
case "${1:-all}" in
  all) shoot sidebar-dusk; THEME=paper shoot sidebar-paper ;;
  # "Glass and paper" is the first row of Essays, at about y=545 from the top
  # of a 1200×860 window; two rows down, and up onto the Daily folder row.
  drag) shoot sidebar-drag -glassine.shootDrag 120,545,0,56
        shoot sidebar-drag-folder -glassine.shootDrag 120,545,0,-52 ;;
  *) echo "usage: $0 [all|drag]"; exit 1 ;;
esac
