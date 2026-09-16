#!/usr/bin/env bash
# The pictures taken by hand in Glassine Demo — the App Store set, at 2880 × 1800
# — brought into the landing page, the README and the manual at 1440 × 900.
#
#   site/from-store-shots.sh [folder]     default: dist/store-shots-v2/App Store 2880x1800
#
# The App Store set comes from docs/appstore/from-captures.py; the names below
# are its. Anything not named here (a second Timelapse, say) is left where it is.
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="${1:-dist/store-shots-v2/App Store 2880x1800}"
[[ -d "$SRC" ]] || { echo "No such folder: $SRC" >&2; exit 1; }
pairs=(
  "01 Editor.png|editor"
  "02 All Documents.png|library"
  "06 Timelapse, Moss.png|daily"
  "07 Review, Book.png|review"
  "05 Caret.png|caret"
  "04 Behind the glass.png|backdrops"
)
for pair in "${pairs[@]}"; do
  file="${pair%%|*}"; name="${pair##*|}"
  [[ -f "$SRC/$file" ]] || { echo "- $name: no $file in $SRC" >&2; continue; }
  for dir in site docs/screenshots docs/site/images; do
    sips -z 900 1440 -s format jpeg -s formatOptions 88 "$SRC/$file" --out "$dir/$name.jpg" >/dev/null
  done
  echo "* $name.jpg ← $file"
done
