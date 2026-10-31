#!/usr/bin/env python3
"""Build one CP1251 Lua script with its catalog and embedded category PNGs.
The explicit manifest preserves module dependencies. LuaJIT validates syntax;
run_tests.py additionally executes startup, behavior, UI-model and data tests.
"""
from pathlib import Path
import json
import base64
import hashlib
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
SRC = ROOT / "src"
OUT = ROOT / "palatka_ai.lua"

MODULES = [
    "00_core.lua",
    "00a_settings_safety.lua",
    "05_items.lua",
    "08_icons.lua",
    "10_market.lua",
    "11_arbitrage.lua",
    "11a_accuracy.lua",
    "12_arbitrage_groups.lua",
    "13_arbitrage_async.lua",
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
    "44_item_registry.lua",
    "45_live.lua",
    "45a_shop_identity.lua",
    "46_shop_scan.lua",
    "46a_shop_store.lua",
    "46b_local_arbitrage.lua",
    "46c_lombard.lua",
    "46d_lombard_packets.lua",
    "47_shop_marker.lua",
    "47_storage.lua",
    "47a_storage_textdraw.lua",
    "47b_storage_probe.lua",
    "47c_storage_search.lua",
    "48_flip_intel.lua",
    "49_promo.lua",
    "49a_promo_universal.lua",
    "49b_promo_mh_options.lua",
    "50_overlay.lua",
    "54_payday_parse.lua",
    "55_craglog.lua",
    "56_mini_journal.lua",
    "57_journal_v16.lua",
    "57a_trade_feed_mh.lua",
    "58_journal_delete.lua",
    "59_history.lua",
    "59a_loot_summary.lua",
    "60_ui21_shell.lua",
    "60aa_touch_scroll.lua",
    "60a_carbon_home.lua",
    "60b_carbon_storage.lua",
    "60e_storage_probe_ui.lua",
    "60c_carbon_draw.lua",
    "61_ui21_trade.lua",
    "62_ui21_shops.lua",
    "63_ui21_arbitrage.lua",
    "63a_ui_local_arbitrage.lua",
    "64_ui21_journal_calc.lua",
    "65_ui22_tools.lua",
    "66_ui22_journal.lua",
    "66a_trade_log_tab_mh.lua",
    "66c_mh_trade_journal.lua",
    "67_ui22_shop_scan.lua",
    "68_ui22_flip_promo.lua",
    "68b_promo_universal_ui.lua",
    "60f_lombard_ui.lua",
    "69a_arbitrage_agent.lua",
    "69b_arbitrage_agent_ui.lua",
    "69c_arbitrage_status.lua",
    "69d_runtime_diagnostic.lua",
    "99_main.lua",
]

HEADER = """-- Palatka AI v2.9.2 mobile release, built from src/*.lua
script_name('palatka ai')
script_author('palatka ai')
script_version('2.9.2')

if not imgui then imgui = require('mimgui') end
DSP = DSP or {}

"""

parts = [HEADER]
# Keep the clean-install catalog inside the standalone script; external catalogs
# still take precedence in DSP.items.load. This file is CP1251 JSON, not UTF-8.
catalog = json.loads((ROOT / "data" / "arz_items.json").read_bytes().decode("cp1251"))
parts.append("DSP.bundled_items = {\n")
for item_id, item_name in sorted(catalog.items(), key=lambda row: int(row[0])):
    literal = json.dumps(item_name, ensure_ascii=False).replace("\\/", "/")
    parts.append(f"[{int(item_id)}]={literal},\n")
parts.append("}\n")
# Keep PNG payloads in an indexed trailing comment. Lua does not retain thousands
# of image strings at startup; the UI reads just one bounded slice when needed.
asset_meta = json.loads((ROOT / "data" / "item_icons.json").read_text()) if (ROOT / "data" / "item_icons.json").exists() else {"items": {}}
asset_lines = []
asset_offset = 0
asset_rows = sorted(asset_meta["items"].items(), key=lambda row: int(row[0])) + sorted(asset_meta.get("named", {}).items())
def asset_key(key):
    return str(int(key)) if key.isdigit() else json.dumps(key)
parts.append("DSP.item_icon_index = {\n")
for item_id, meta in asset_rows:
    png = (ROOT / "icons" / "items" / (item_id + ".png")).read_bytes()
    if hashlib.sha256(png).hexdigest() != meta["sha256"] or not png.startswith(b"\x89PNG\r\n\x1a\n"):
        sys.exit("invalid icon asset: " + item_id)
    encoded = base64.b64encode(png).decode("ascii")
    parts.append(f"[{asset_key(item_id)}]={{{asset_offset},{len(encoded)}}},\n")
    asset_lines.append(encoded + "\n")
    asset_offset += len(encoded) + 1
parts.append("}\nDSP.item_icon_names = {\n")
for item_id, meta in asset_rows:
    parts.append(f"[{asset_key(item_id)}]={json.dumps(meta['name'], ensure_ascii=False)},\n")
parts.append("}\nDSP.item_icon_blob_offset = __ICON_OFFSET__\n")
for name in MODULES:
    path = SRC / name
    if not path.exists():
        sys.exit(f"missing module: {path}")
    raw_source = path.read_bytes()
    try:
        text = raw_source.decode("utf-8")
    except UnicodeDecodeError:
        # Legacy Lua sources can already be CP1251. Normalize their text
        # before concatenation; the final standalone is CP1251 as before.
        text = raw_source.decode("cp1251")
        print(f"legacy CP1251 module: {name}")
    try:
        text.encode("cp1251")
    except UnicodeEncodeError:
        # Some legacy UTF-8 files contain Latin-1 renderings of CP1251
        # bytes (e.g. 'çàãðóæåí' instead of Russian). Recover Cyrillic
        # byte-for-byte rather than replacing unsupported characters.
        def cp1251_from_latin1(ch):
            number = ord(ch)
            if 0x80 <= number <= 0xFF:
                recovered = bytes([number]).decode("cp1251", errors="replace")
                if recovered != "\\ufffd":
                    return recovered
            return ch
        repaired = "".join(cp1251_from_latin1(c) for c in text)
        try:
            repaired.encode("cp1251")
        except UnicodeEncodeError as exc:
            sys.exit(f"non-CP1251 characters in {name}: {repr(repaired[exc.start:exc.end])} at {exc.start}")
        text = repaired
        print(f"fixed legacy Latin1 mojibake: {name}")
    fn = "__mod_" + name.replace(".lua", "").replace("-", "_")
    parts.append(f"local function {fn}()\n")
    parts.append(text)
    parts.append(f"\nend\n{fn}()\n\n")

lua = "".join(parts)
blob_header = "\n--[=[PALATKA_ITEM_IMAGES_V1\n"
offset = 0
while True:
    prefix = lua.replace("__ICON_OFFSET__", str(offset)) + blob_header
    actual = len(prefix.encode("cp1251"))
    if actual == offset:
        break
    offset = actual
lua = prefix + "".join(asset_lines) + "]=]\n"
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
