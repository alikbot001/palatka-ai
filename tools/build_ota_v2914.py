#!/usr/bin/env python3
"""Rebuild the 2.9.14 OTA from the verified 2.9.13 release.
Patch existing 2.9.13 clients without changing their saved settings."""
from pathlib import Path
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BASE = "bedc7cb3a083a0dd6bec8c0adb4648bf5d6c117d"
OUT = ROOT / "updates" / "palatka_update.lua"
MARKER = b"  -- Install settings guard before any other overlay can save preferences."
OLD = b"PALATKA_UPDATE_VERSION = '2.9.13'"
NEW = b"PALATKA_UPDATE_VERSION = '2.9.14'"
PARENT = b"return install_chrome_2913()"
CHILD = b"return install_trade_2914()"
MODULES = [
    ("migration", "src/70_trade_ota_v2914.lua"),
    ("listing", "src/41_trade_listing.lua"),
    ("stock", "src/70b_trade_stock_ota_v2914.lua"),
]

def normalize(path):
    raw = (ROOT / path).read_bytes()
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        text = raw.decode("cp1251")
    try:
        return text.encode("cp1251")
    except UnicodeEncodeError:
        # Existing legacy sources sometimes contain Latin-1 renderings of CP1251.
        def repair(ch):
            n = ord(ch)
            if 128 <= n <= 255:
                converted = bytes([n]).decode("cp1251", errors="replace")
                if converted != "\ufffd":
                    return converted
            return ch
        return "".join(repair(ch) for ch in text).encode("cp1251")

raw = subprocess.check_output(
    ["git", "show", f"{BASE}:updates/palatka_update.lua"], cwd=ROOT
)
assert raw.count(OLD) == 1, "unexpected parent OTA version"
assert raw.count(PARENT) == 2, "unexpected parent install routes"
assert raw.count(MARKER) == 1, "unexpected insertion location"

parts = [
    b"  -- 2.9.14: install Halloween trade protocol fixes on older OTA clients.\n",
    b"  local function install_trade_2914()\n",
    b"    local ok=install_chrome_2913()\n",
    b"    if not ok then return false end\n",
    b"    if DSP._trade_2914_installed then DSP.version='2.9.14';return true end\n",
    b"    local applied,err=pcall(function()\n",
]
for name, filename in MODULES:
    code = normalize(filename)
    fname = "_v2914_" + name
    parts += [
        f"      local function {fname}()\n".encode("ascii"),
        code,
        b"" if code.endswith(b"\n") else b"\n",
        b"      end\n",
        f"      if {fname}()==false then error('2.9.14 {name} failed')end\n".encode("ascii"),
    ]
parts += [
    b"    end)\n",
    b"    if not applied then\n",
    b"      if DSP.flog then DSP.flog('Palatka 2.9.14 update error: '..tostring(err))end\n",
    b"      return false\n",
    b"    end\n",
    b"    DSP._trade_2914_installed=true\n",
    b"    DSP.version='2.9.14'\n",
    b"    DSP.active_ui_build='2.9.14'\n",
    b"    if DSP.flog then DSP.flog('Palatka 2.9.14 trade update installed')end\n",
    b"    return true\n",
    b"  end\n",
]
raw = raw.replace(OLD, NEW, 1)
raw = raw.replace(PARENT, CHILD)
raw = raw.replace(MARKER, b"".join(parts) + MARKER, 1)
assert raw.count(CHILD) == 2
assert raw.count(b"local function install_trade_2914()") == 1
OUT.write_bytes(raw)
manifest = {
    "schema": 1,
    "version": "2.9.14",
    "mode": "overlay",
    "url": "https://raw.githubusercontent.com/alikbot001/palatka-ai/main/updates/palatka_update.lua",
    "size": len(raw),
    "published_at": "2026-11-02",
    "changelog": [
        "Исправлено ожидание диалога цены при выставлении предмета на продажу после обновления Arizona Mobile II.",
        "Добавлено распознавание новых ID диалогов и диагностика торговых окон.",
        "Добавлена ограниченная сборка неполных JSON-фрагментов с защитой от превышения памяти.",
        "Исправления доступны в автономном Lua и через внутриигровое обновление с версии 2.9.13.",
        "Сохранены настройки, пресеты, управление окнами и существующие функции."
    ],
}
(ROOT / "version.json").write_text(
    json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
)
print("2.9.14 OTA generated:", len(raw), "bytes")
