#!/usr/bin/env python3
"""Build the 2.9.17 UI OTA on top of the verified 2.9.16 installer."""
from pathlib import Path
import json
import subprocess
from datetime import date

ROOT = Path(__file__).resolve().parents[1]
BASE = "00407c2a77ee33e4300667e58bbd4289abdcf417"
OUT = ROOT / "updates" / "palatka_update.lua"
MARK = b"  -- Install settings guard before any other overlay can save preferences."
OLD = b"PALATKA_UPDATE_VERSION = '2.9.16'"
NEW = b"PALATKA_UPDATE_VERSION = '2.9.17'"
PREV = b"return install_sell_2916()"
NEXT = b"return install_ui_2917()"

def cp1251(path):
    data = (ROOT / path).read_bytes()
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        text = data.decode("cp1251")
    return text.encode("cp1251")

base = subprocess.check_output(
    ["git", "show", BASE + ":updates/palatka_update.lua"], cwd=ROOT
)
assert base.count(OLD) == 1, "Expected released OTA header"
assert base.count(PREV) == 2, "Expected two chained release entry points"
assert base.count(MARK) == 1, "Expected one pre-installation marker"

ui = cp1251("src/69e_compact_ui_v2917.lua")
parts = [
    b"  -- v2.9.17: compact navigation, categorized settings and manual updates.\n",
    b"  local function install_ui_2917()\n",
    b"    if not install_sell_2916() then return false end\n",
    b"    if DSP._ui_2917_installed then DSP.version='2.9.17';return true end\n",
    b"    local ok,err=pcall(function()\n",
    ui,
    b"" if ui.endswith(b"\n") else b"\n",
    b"    end)\n",
    b"    if not ok then\n",
    b"      if DSP.flog then DSP.flog('Palatka UI 2.9.17: '..tostring(err)) end\n",
    b"      return false\n",
    b"    end\n",
    b"    DSP._ui_2917_installed=true\n",
    b"    DSP.version='2.9.17'\n",
    b"    DSP.active_ui_build='2.9.17'\n",
    b"    return true\n",
    b"  end\n",
]
raw = base.replace(OLD, NEW, 1).replace(PREV, NEXT).replace(MARK, b"".join(parts) + MARK, 1)
assert raw.count(NEXT) == 2
assert b"local function install_ui_2917()" in raw
assert b"_compact_ui_2917_installed" in raw
OUT.write_bytes(raw)
release = {
    "schema": 1,
    "version": "2.9.17",
    "mode": "overlay",
    "url": "https://raw.githubusercontent.com/alikbot001/palatka-ai/main/updates/palatka_update.lua",
    "size": len(raw),
    "published_at": "2026-11-08",
    "changelog": [
        "Главное меню сокращено до основных разделов; остальные доступны через расширенное меню.",
        "Настройки разделены на интерфейс, торговлю, сканирование, рынок и обновления.",
        "Добавлена отдельная проверка версии и ручная установка через GitHub.",
        "Кнопка обновления рыночных цен больше не путается с обновлением скрипта.",
        "Существующие пресеты, журналы и настройки не сбрасываются."
    ],
}
(ROOT / "version.json").write_text(json.dumps(release, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print("Built Palatka OTA 2.9.17", len(raw), "bytes")
