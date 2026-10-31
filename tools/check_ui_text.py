#!/usr/bin/env python3
"""Static guard against broken CP1251/UTF-8 Russian UI text in Palatka AI.

The editable Lua modules are UTF-8; build.py writes the standalone script
as CP1251. This check is intentionally independent of Android/MonetLoader.
"""
from __future__ import annotations

import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
BAD_RUN = re.compile(r"[À-ÿ]{2,}")
ERRORS: list[str] = []

for path in sorted((ROOT / "src").glob("*.lua")):
    relative = path.relative_to(ROOT)
    try:
        source = path.read_text(encoding="utf-8")
        # The generated monolithic Lua is encoded in CP1251 by build.py.
        source.encode("cp1251")
    except (UnicodeError, OSError) as exc:
        ERRORS.append(f"{relative}: source encoding: {exc}")
        continue
    for line_number, line in enumerate(source.splitlines(), 1):
        # Double-encoded Cyrillic usually appears as Ðàáîòà / Òîðãîâëÿ.
        if BAD_RUN.search(line) or re.search(r"[\x80-\x9f]", line):
            ERRORS.append(f"{relative}:{line_number}: possible mojibake: {line[:90]!r}")

html_path = ROOT / "webui" / "index.html"
version_path = ROOT / "version.json"
package_path = ROOT / "package.json"
if all(p.is_file() for p in (html_path, version_path, package_path)):
    html = html_path.read_bytes()
    package = json.loads(package_path.read_text(encoding="utf-8"))
    version = json.loads(version_path.read_text(encoding="utf-8"))
    update_path = ROOT / package["bootstrap"]["path"]
    if version["version"] != package["version"] or version["version"] != package["bootstrap"]["version"]:
        ERRORS.append("version.json / package.json version mismatch")
    if update_path.exists():
        actual = update_path.stat().st_size
        if actual != package["bootstrap"]["size"] or actual != version["size"]:
            ERRORS.append(f"bootstrap size: actual {actual}, expected {package['bootstrap']['size']}")
    if len(html) != next(a["size"] for a in package["assets"] if a["path"] == "webui/index.html"):
        ERRORS.append(f"WebUI HTML size mismatch: {len(html)} bytes")
    if b"@media(max-width:1060px)" not in html:
        ERRORS.append("WebUI floating window breakpoint missing")

if ERRORS:
    for error in ERRORS:
        print("FAIL:", error)
    sys.exit(1)
print("PASS: Russian UI text, CP1251 compatibility, version and WebUI asset manifest")
