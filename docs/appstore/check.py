#!/usr/bin/env python3
"""Check the App Store listing copy against Apple's field limits.

    python3 docs/appstore/check.py

Reads listing.md next to this file. Each section heading carries its limit in
parentheses; sections without one are not counted.
"""
import pathlib
import re
import sys

text = (pathlib.Path(__file__).parent / "listing.md").read_text()
ok = True
for match in re.finditer(r"^## ([^\n]+?) \((\d[\d,]*)\)\n\n(.*?)(?=\n## |\Z)", text, re.S | re.M):
    name, limit, body = match.group(1), int(match.group(2).replace(",", "")), match.group(3).strip()
    n = len(body)
    flag = "" if n <= limit else "   TOO LONG"
    ok = ok and n <= limit
    print(f"{name:18} {n:5} / {limit}{flag}")
sys.exit(0 if ok else 1)
