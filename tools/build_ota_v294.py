#!/usr/bin/env python3
"""Build the Palatka AI 2.9.4 OTA from the verified 2.9.3 payload plus v2.9.4 corrective overlays."""
from pathlib import Path
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "updates" / "palatka_update.lua"
MANIFEST = ROOT / "version.json"
BASE_COMMIT = "e4b3ac757252d43c5b1de1bb9bd85a1c0be72924"
OLD_VERSION = b"PALATKA_UPDATE_VERSION = '2.9.3'"
NEW_VERSION = b"PALATKA_UPDATE_VERSION = '2.9.4'"
INSERT_MARKER = b"  -- Install settings guard before any other overlay can save preferences."

MODULES = [
    ("settings_persistence", "src/00b_settings_persistence_v294.lua"),
    ("promo_scheduler", "src/49c_promo_mh_scheduler_v294.lua"),
    ("mh_journal_screen", "src/66d_mh_journal_screen_v294.lua"),
]

def normalize(path: str) -> bytes:
    raw = (ROOT / path).read_bytes()
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        text = raw.decode("cp1251")
    try:
        return text.encode("cp1251")
    except UnicodeEncodeError:
        def repair(ch: str) -> str:
            code = ord(ch)
            if 128 <= code <= 255:
                fixed = bytes([code]).decode("cp1251", errors="replace")
                if fixed != "\ufffd":
                    return fixed
            return ch
        repaired = "".join(repair(ch) for ch in text)
        return repaired.encode("cp1251")

base = subprocess.check_output(
    ["git", "show", f"{BASE_COMMIT}:updates/palatka_update.lua"],
    cwd=ROOT,
)
if base.count(OLD_VERSION) != 1:
    raise SystemExit("unexpected 2.9.3 OTA version marker")
if base.count(b"return install_v293()") != 2:
    raise SystemExit("unexpected 2.9.3 terminal installer count")
if base.count(INSERT_MARKER) != 1:
    raise SystemExit("unexpected OTA insertion marker")

parts = [
    b"  -- v2.9.4: Market Helper UX, touch scrolling, completed arbitrage flow, journal and statistics.\n",
    b"  local function install_v294()\n",
    b"    local parent_ok=install_v293()\n",
    b"    if not parent_ok then return false end\n",
    b"    if DSP._v294_installed then DSP.version='2.9.4';return true end\n",
    b"    local ok,err=pcall(function()\n",
]
for name, path in MODULES:
    code = normalize(path)
    fn = f"_v294_{name}".encode("ascii")
    parts += [
        b"      local function " + fn + b"()\n",
        code,
        b"" if code.endswith(b"\n") else b"\n",
        b"      end\n",
        b"      local ok_module,why_module=pcall(" + fn + b")\n",
        b"      if not ok_module then error('" + fn + b": '..tostring(why_module))end\n",
    ]
parts += [
    b"    end)\n",
    b"    if not ok then\n",
    b"      if DSP.flog then DSP.flog('Palatka v2.9.4 install error: '..tostring(err))end\n",
    b"      return false\n",
    b"    end\n",
    b"    DSP._v294_installed=true\n",
    b"    DSP.version='2.9.4'\n",
    b"    DSP.active_ui_build='2.9.4'\n",
    b"    if DSP.flog then DSP.flog('Palatka v2.9.4 Market Helper UX installed')end\n",
    b"    return true\n",
    b"  end\n",
]
block = b"".join(parts)

raw = base.replace(
    b"-- Palatka AI 2.9.3 OTA: Market Helper UX, touch scroll, journal, statistics and arbitrage fixes.",
    b"-- Palatka AI 2.9.4 OTA: Market Helper UX, touch scroll, journal, statistics and arbitrage fixes.",
    1,
)
raw = raw.replace(OLD_VERSION, NEW_VERSION, 1)
raw = raw.replace(b"return install_v293()", b"return install_v294()")
raw = raw.replace(INSERT_MARKER, block + INSERT_MARKER, 1)

OUT.write_bytes(raw)
release = {
    "schema": 1,
    "version": "2.9.4",
    "mode": "overlay",
    "url": "https://raw.githubusercontent.com/alikbot001/palatka-ai/main/updates/palatka_update.lua",
    "size": len(raw),
    "published_at": "2026-11-01",
    "changelog": [
        "Сохранение темы и прозрачности больше не сбрасывается устаревшим ui_state.json при перезаходе.",
        "Журнал сделок открыт как отдельный экран по примеру Market Helper: 6 колонок, поиск, даты и итоги.",
        "Удалено плавающее окно журнала с закреплением и кнопками перемещения.",
        "Автопиар отправляет все строки шаблона последовательно с паузой и индивидуальным интервалом повтора.",
        "Автопиар: исправлены лимиты, случайная строка, ручная отправка, остановка и возобновление после входа.",
        ],
}
MANIFEST.write_text(json.dumps(release, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"Generated Palatka AI 2.9.4 OTA: {len(raw)} bytes")
