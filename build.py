#!/usr/bin/env python3
"""Build the standalone Palatka AI into one CP1251 Lua file.

v1.2: adds 35_screens.lua between 30_ui.lua and 50_overlay.lua so that
DSP.theme (defined in 00_core.lua) and DSP.ui.* (defined in 30_ui.lua) are
already populated when the screen dispatcher wires them up.
"""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
SRC = ROOT / "src"
OUT = ROOT / "palatka_ai.lua"

MODULES = [
    "00_core.lua",
    "05_items.lua",
    "08_icons.lua",
    "10_market.lua",
    "11_arbitrage.lua",
    "12_arbitrage_groups.lua",
    "15_prices.lua",
    "05_trades.lua",
    "06_rewards.lua",
    "20_presets.lua",
    "21_preset_library.lua",
    "30_ui.lua",
    "35_screens.lua",
    "36_mobile.lua",
    "37_mobile_trade.lua",
    "37_trade_v16.lua",
    "38_mobile_market.lua",
    "38_arbitrage_v16.lua",
    "39_mobile_history.lua",
    "40_mobile_notes.lua",
    "39_trade_runtime.lua",
    "40_auto.lua",
    "41_trade_listing.lua",
    "42_trade_buy.lua",
    "43_calculator_nav.lua",
    "45_live.lua",
    "50_overlay.lua",
    "55_craglog.lua",
    "56_mini_journal.lua",
    "57_journal_v16.lua",
    "99_main.lua",
]

HEADER = """-- Palatka AI v1.6.0, built from src/*.lua (independent of Market Helper)
script_name('palatka ai')
script_author('palatka ai')
script_version('1.6.0')

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

import shutil
if shutil.which('luajit'):
    args = ['luajit', '-bl', str(OUT), '/dev/null']
    label = 'luajit'
else:
    # Syntax-only fallback: texlua can compile source without MoonLoader.
    checker = ROOT / 'tests' / '_check_build.lua'
    checker.write_text("assert(loadfile(arg[1]))\nprint('Lua syntax: ok')\n")
    args = ['texlua', str(checker), str(OUT)]
    label = 'texlua'
check = subprocess.run(args, capture_output=True, text=True)
if check.returncode != 0:
    sys.exit(label + ' syntax check failed:\n' + check.stdout + check.stderr)
print(label + ' syntax: ok')
if label == 'texlua': checker.unlink(missing_ok=True)
