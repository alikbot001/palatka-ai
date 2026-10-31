#!/usr/bin/env python3
"""Build the Palatka AI 2.9.5 OTA from the verified 2.9.4 payload plus v2.9.5 corrective overlays."""
from pathlib import Path
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "updates" / "palatka_update.lua"
MANIFEST = ROOT / "version.json"
BASE_COMMIT = "f852c08473ccf3473b86b9d7524cc92e481694c8"
OLD_VERSION = b"PALATKA_UPDATE_VERSION = '2.9.4'"
NEW_VERSION = b"PALATKA_UPDATE_VERSION = '2.9.5'"
INSERT_MARKER = b"  -- Install settings guard before any other overlay can save preferences."

MODULES = [
    ("storage_render_cache", "src/47d_storage_render_cache_v295.lua"),
    ("stats_render_cache", "src/65b_stats_render_cache_v295.lua"),
    ("journal_render_cache", "src/66e_mh_journal_fast_v295.lua"),
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
    raise SystemExit("unexpected 2.9.4 OTA version marker")
if base.count(b"return install_v294()") != 2:
    raise SystemExit("unexpected 2.9.4 terminal installer count")
if base.count(INSERT_MARKER) != 1:
    raise SystemExit("unexpected OTA insertion marker")

parts = [
    b"  -- v2.9.5: Market Helper UX, touch scrolling, completed arbitrage flow, journal and statistics.\n",
    b"  local function install_v295()\n",
    b"    local parent_ok=install_v294()\n",
    b"    if not parent_ok then return false end\n",
    b"    if DSP._v295_installed then DSP.version='2.9.5';return true end\n",
    b"    local ok,err=pcall(function()\n",
]
for name, path in MODULES:
    code = normalize(path)
    fn = f"_v295_{name}".encode("ascii")
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
    b"      if DSP.flog then DSP.flog('Palatka v2.9.5 install error: '..tostring(err))end\n",
    b"      return false\n",
    b"    end\n",
    b"    DSP._v295_installed=true\n",
    b"    DSP.version='2.9.5'\n",
    b"    DSP.active_ui_build='2.9.5'\n",
    b"    if DSP.flog then DSP.flog('Palatka v2.9.5 Market Helper UX installed')end\n",
    b"    return true\n",
    b"  end\n",
]
block = b"".join(parts)

raw = base.replace(
    b"-- Palatka AI 2.9.4 OTA: Market Helper UX, touch scroll, journal, statistics and arbitrage fixes.",
    b"-- Palatka AI 2.9.4 OTA: Market Helper UX, touch scroll, journal, statistics and arbitrage fixes.",
    1,
)
raw = raw.replace(OLD_VERSION, NEW_VERSION, 1)
raw = raw.replace(b"return install_v294()", b"return install_v295()")
raw = raw.replace(INSERT_MARKER, block + INSERT_MARKER, 1)

OUT.write_bytes(raw)
release = {
    "schema": 1,
    "version": "2.9.5",
    "mode": "overlay",
    "url": "https://raw.githubusercontent.com/alikbot001/palatka-ai/main/updates/palatka_update.lua",
    "size": len(raw),
    "published_at": "2026-11-01",
    "changelog": [
        "Исправлено падение FPS при открытом журнале: фильтры, сортировка и суммы кэшируются вместо работы на каждом кадре.",
        "Статистика больше не пересчитывает весь инвентарь и историю каждую отрисовку.",
        "Поиск по сохранённым хранилищам и оценки перестали повторяться десятки раз в секунду.",
        "На полной установке мини-журнал читает только хвост событий, а не весь архив при входе в игру.",
        "Исходные данные, сканы и операции сохранены; кэш сбрасывается при изменениях и по короткому таймеру.",
    ],
}
MANIFEST.write_text(json.dumps(release, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"Generated Palatka AI 2.9.5 OTA: {len(raw)} bytes")
