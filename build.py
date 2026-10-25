#!/usr/bin/env python3
"""Build the standalone DsPic Helper into one CP1251 Lua file."""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
SRC = ROOT / "src"
OUT = ROOT / "DsPic_Standalone.lua"

MODULES = [
    "00_core.lua",
    "05_items.lua",
    "10_market.lua",
    "15_prices.lua",
    "05_trades.lua",
    "20_presets.lua",
    "30_ui.lua",
    "40_auto.lua",
    "45_live.lua",
    "50_overlay.lua",
    "99_main.lua",
]

HEADER = """-- Palatka AI, built from src/*.lua (independent of Market Helper)
script_name('palatka ai')
script_author('palatka ai')
script_version('1.0.0')

if not imgui then imgui = require('mimgui') end
DSP = DSP or {}

"""

parts = [HEADER]
for name in MODULES:
    path = SRC / name
    if not path.exists():
        sys.exit(f"missing module: {path}")
    text = path.read_text(encoding="utf-8")
    fn = "__mod_" + name.replace(".lua", "").replace("-", "_")
    parts.append(f"local function {fn}()\n")
    parts.append(text)
    parts.append(f"\nend\n{fn}()\n\n")

lua = "".join(parts)
try:
    raw = lua.encode("cp1251")
except UnicodeEncodeError as e:
    sys.exit(f"cp1251 encode failed: {e}")

OUT.write_bytes(raw)
print(f"built {OUT} ({len(raw)} bytes)")

check = subprocess.run(
    ["luajit", "-bl", str(OUT), "/dev/null"],
    capture_output=True,
    text=True,
)
if check.returncode != 0:
    sys.exit("luajit syntax check failed:\n" + check.stderr)
print("luajit syntax: ok")
