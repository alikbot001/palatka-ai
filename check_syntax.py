#!/usr/bin/env python3
"""Release preflight: strict LuaJIT compilation and cross-artifact version checks.

Lua 5.4, texlua and permissive mocks are NOT equivalent to LuaJIT 5.1.
This command exits nonzero if LuaJIT is unavailable or ANY artifact fails.
Android/MonetLoader runtime validation remains a separate release gate.
"""
from pathlib import Path
import json
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
runtime = shutil.which("luajit")
if not runtime:
    sys.exit("FAIL: LuaJIT is required; no Lua syntax checks were run")

paths = sorted((ROOT / "src").glob("*.lua"))
paths.append(ROOT / "updates" / "palatka_update.lua")
standalone = ROOT / "palatka_ai.lua"
if standalone.exists():
    paths.append(standalone)
failed = []
for path in paths:
    result = subprocess.run(
        [runtime, "-b", str(path), "/dev/null"],
        cwd=ROOT, capture_output=True, text=True, timeout=45,
    )
    if result.returncode:
        failed.append((str(path.relative_to(ROOT)), result.stderr.strip()))
if failed:
    for path, reason in failed:
        print("FAIL", path, reason)
    sys.exit(f"{len(failed)}/{len(paths)} LuaJIT compilation checks failed")

manifest = json.loads((ROOT / "version.json").read_text(encoding="utf-8"))
version = manifest.get("version")
if not isinstance(version, str) or not re.fullmatch(r"\\d+\\.\\d+\\.\\d+", version):
    sys.exit("FAIL: invalid version.json version")
ota = (ROOT / "updates" / "palatka_update.lua").read_bytes()
if len(ota) != manifest.get("size"):
    sys.exit("FAIL: OTA size differs from version.json")
marker = ("PALATKA_UPDATE_VERSION = '" + version + "'").encode("ascii")
if marker not in ota:
    sys.exit("FAIL: OTA version differs from version.json")
build = (ROOT / "build.py").read_text(encoding="utf-8")
if ("script_version('" + version + "')") not in build:
    sys.exit("FAIL: standalone builder version differs from manifest")
core = (ROOT / "src" / "00_core.lua").read_text(encoding="utf-8")
if ("DSP.version = '" + version + "'") not in core:
    sys.exit("FAIL: runtime UI version differs from manifest")
if standalone.exists():
    header = standalone.read_bytes()[:2000]
    if ("script_version('" + version + "')").encode("ascii") not in header:
        sys.exit("FAIL: generated standalone version differs from manifest")
print(f"PASS: {len(paths)} LuaJIT files, OTA bytes and version {version} consistent")
