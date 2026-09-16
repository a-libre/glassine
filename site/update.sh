#!/usr/bin/env bash
# The landing page's moving parts, filled in from where they are decided:
# the version from Resources/Info.plist, and "What's new" from the top block
# of site/whats-new.md — between the <!-- version --> and <!-- whats-new -->
# markers in site/index.html, everything else left as written. release.sh
# runs this on every release; run it by hand after editing whats-new.md.
#
#   site/update.sh            fill the page in
#   site/update.sh --check    say whether the page is behind, and exit 1 if so
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist 2>/dev/null \
  || plutil -extract CFBundleShortVersionString raw Resources/Info.plist)
python3 - "$VERSION" "${1:-}" <<'PY'
import html, re, sys
version, mode = sys.argv[1], sys.argv[2]
path = "site/index.html"
page = open(path, encoding="utf-8").read()

def fill(page, marker, content):
    start, end = f"<!-- {marker} -->", f"<!-- /{marker} -->"
    a = page.index(start) + len(start)
    b = page.index(end)
    return page[:a] + content + page[b:]

def inline(s):
    s = html.escape(s, quote=False)
    s = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", s)
    s = re.sub(r"\[\[(.+?)\]\]", r'<span class="kbd">\1</span>', s)
    s = re.sub(r"\[(.+?)\]\((.+?)\)", r'<a href="\2">\1</a>', s)
    s = re.sub(r"`(.+?)`", r"<code>\1</code>", s)
    s = re.sub(r"(?<![*\w])\*(?!\*)(.+?)\*", r"<em>\1</em>", s)
    return s

md = open("site/whats-new.md", encoding="utf-8").read()
blocks = re.split(r"^## ", md, flags=re.M)[1:]
if not blocks:
    sys.exit("site/whats-new.md has no '## version' block")
head = blocks[0].splitlines()
heading = head[0].strip()
lines = [l[2:].strip() for l in head[1:] if l.startswith("- ")]
if not heading.startswith(version):
    print(f"* site/whats-new.md's top block is {heading.split(' ')[0]}; the app is {version}. Add the lines for {version}.", file=sys.stderr)
    if mode == "--check":
        sys.exit(1)

items = "\n".join(f"      <li>{inline(l)}</li>" for l in lines)
new = fill(page, "version", version)
new = fill(new, "whats-new-head", inline(heading))
new = fill(new, "whats-new", "\n" + items + "\n    ")
if mode == "--check":
    if new != page:
        print("* site/index.html is behind: run site/update.sh", file=sys.stderr)
        sys.exit(1)
    print("site/index.html is current")
else:
    if new != page:
        open(path, "w", encoding="utf-8").write(new)
        print(f"site/index.html: version {version}; what's new: {heading} ({len(lines)} lines)")
    else:
        print("site/index.html already current")
PY
