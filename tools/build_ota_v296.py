#!/usr/bin/env python3
"""Build the Palatka AI 2.9.6 OTA from the verified 2.9.5 payload plus v2.9.6 corrective overlays."""
from pathlib import Path
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "updates" / "palatka_update.lua"
MANIFEST = ROOT / "version.json"
BASE_COMMIT = "778915d9291cbd2b50e683cf3d5433d3c88d900c"
OLD_VERSION = b"PALATKA_UPDATE_VERSION = '2.9.5'"
NEW_VERSION = b"PALATKA_UPDATE_VERSION = '2.9.6'"
INSERT_MARKER = b"  -- Install settings guard before any other overlay can save preferences."

MODULES = [
    ("reconnect", "src/70_reconnect_v296.lua"),
    ("reconnect_ui", "src/70a_reconnect_ui_v296.lua"),
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
    raise SystemExit("unexpected 2.9.5 OTA version marker")
if base.count(b"return install_v295()") != 2:
    raise SystemExit("unexpected 2.9.5 terminal installer count")
if base.count(INSERT_MARKER) != 1:
    raise SystemExit("unexpected OTA insertion marker")

parts = [
    b"  -- v2.9.6: Market Helper UX, touch scrolling, completed arbitrage flow, journal and statistics.\n",
    b"  local function install_v296()\n",
    b"    local parent_ok=install_v295()\n",
    b"    if not parent_ok then return false end\n",
    b"    if DSP._v296_installed then DSP.version='2.9.6';return true end\n",
    b"    local ok,err=pcall(function()\n",
]
for name, path in MODULES:
    code = normalize(path)
    fn = f"_v296_{name}".encode("ascii")
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
    b"      if DSP.flog then DSP.flog('Palatka v2.9.6 install error: '..tostring(err))end\n",
    b"      return false\n",
    b"    end\n",
    b"    DSP._v296_installed=true\n",
    b"    DSP.version='2.9.6'\n",
    b"    DSP.active_ui_build='2.9.6'\n",
    b"    if DSP.flog then DSP.flog('Palatka v2.9.6 Market Helper UX installed')end\n",
    b"    return true\n",
    b"  end\n",
]
block = b"".join(parts)

# Keep a copy of the verified previous release as the ancestor layer.
raw = base
raw = raw.replace(OLD_VERSION, NEW_VERSION, 1)
raw = raw.replace(b"return install_v295()", b"return install_v296()")
raw = raw.replace(INSERT_MARKER, block + INSERT_MARKER, 1)

OUT.write_bytes(raw)
release = {
    "schema": 1,
    "version": "2.9.6",
    "mode": "overlay",
    "url": "https://raw.githubusercontent.com/alikbot001/palatka-ai/main/updates/palatka_update.lua",
    "size": len(raw),
    "published_at": "2026-11-01",
    "changelog": [
        "Реконнект: добровольный запуск, событие потери связи, тайм-аут, максимальные попытки, экспоненциальные паузы.",
        "Точный выбор спавна из реального SA-MP-диалога с сохранением выбора отдельно для каждого сервера.",
        "Отдельный экран настройки реконнекта, статуса, лимитов и диагностики.",
        "Блокировка автопопыток после ошибок авторизации, кика или блокировки; без работы с паролями и капчей.",
    ],
}
MANIFEST.write_text(json.dumps(release, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"Generated Palatka AI 2.9.6 OTA: {len(raw)} bytes")
