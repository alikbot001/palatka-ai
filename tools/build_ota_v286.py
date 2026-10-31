#!/usr/bin/env python3
"""Produce a single Palatka v2.8.6 OTA: retains all 2.8.5 patches and adds MCR/agent.
Reads the original v2.8.5 OTA bytes, then embeds only independently verified modules.
The generated Lua keeps game-facing CP1251 string literals, like build.py.
"""
from pathlib import Path
import json
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "updates" / "palatka_update_v285.lua"
OUT = ROOT / "updates" / "palatka_update.lua"
MANIFEST = ROOT / "version.json"
MARKER = b"PALATKA_UPDATE_VERSION = '2.8.5'"
HOOK = b"return function(DSP)\n"
EARLY = b"  if DSP._v285_installed then\n    DSP.version='2.8.5'\n    return true\n  end"
TRAIL = b"  return true\nend\n"
OLD_URL = "https://raw.githubusercontent.com/alikbot001/palatka-ai/main/updates/palatka_update.lua"

if not BASE.exists():
    if not OUT.exists() or MARKER not in OUT.read_bytes():
        raise SystemExit("Missing pristine 2.8.5 OTA; refusing to overwrite a release")
    shutil.copyfile(OUT, BASE)
original = BASE.read_bytes()
if original.count(MARKER) != 1 or original.count(HOOK) != 1 or original.count(EARLY) != 1:
    raise SystemExit("Unexpected 2.8.5 OTA base structure")
if not original.endswith(TRAIL):
    raise SystemExit("Unexpected 2.8.5 OTA tail")

def normalize(path):
    raw = (ROOT / path).read_bytes()
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        text = raw.decode("cp1251")
    try:
        return text.encode("cp1251")
    except UnicodeEncodeError:
        def repair(ch):
            v = ord(ch)
            if 128 <= v <= 255:
                return bytes([v]).decode("cp1251", errors="replace")
            return ch
        fixed = "".join(map(repair, text))
        return fixed.encode("cp1251")

# Geometry is the only component of craglog that must be replaced.
# Do not reinstall its event store or duplicate existing logs.
crag = normalize("src/55_craglog.lua")
start = crag.index(b"function C.geometry(sw,sh)")
end = crag.index(b"function C.end_resize()", start)
geometry = (b"local C=DSP.craglog\n"
            b"local function settings() DSP.settings.craglog=DSP.settings.craglog or {} "
            b"return DSP.settings.craglog end\n" + crag[start:end] + b"\n")

modules = [
    ("mini_geometry", geometry),
    ("local_routes", normalize("src/46b_local_arbitrage.lua")),
    ("arbitrage_ui", normalize("src/63_ui21_arbitrage.lua")),
    ("local_arbitrage_ui", normalize("src/63a_ui_local_arbitrage.lua")),
    ("journal_ui", normalize("src/66_ui22_journal.lua")),
    ("mini_journal_ui", normalize("src/56_mini_journal.lua")),
    ("mcr_classic", normalize("src/69_mcr_classic.lua")),
    ("arb_agent_model", normalize("src/69a_arbitrage_agent.lua")),
    ("arb_agent_overlay", normalize("src/69b_arbitrage_agent_ui.lua")),
]
parts = [
    b"  -- v2.8.6: Independent, additive UI + multi-deal arbitration patch.\n",
    b"  local function install_v286()\n",
    b"    if DSP._v286_installed then DSP.version='2.8.6'; return true end\n",
    b"    local ok,err=pcall(function()\n",
]
for name,code in modules:
    parts += [f"      local function _v286_{name}()\n".encode("ascii"),
              code,
              f"\n      end\n      _v286_{name}()\n".encode("ascii")]
parts += [
    b"      if DSP.arb_agent and DSP.arb_agent.install then DSP.arb_agent.install() end\n",
    b"      if sampRegisterChatCommand then\n",
    b"        sampRegisterChatCommand('crrmcr',function() DSP.settings.ui_style='mcr'; "
    b"if DSP.mobile and DSP.mobile.defer_save then DSP.mobile.defer_save() end; "
    b"if DSP.ui and DSP.ui.set_open then DSP.ui.set_open(true) end end)\n",
    b"      end\n",
    b"    end)\n",
    b"    if not ok then\n",
    b"      if DSP.flog then DSP.flog('Palatka 2.8.6 UI / agent install: '..tostring(err)) end\n",
    b"      return false\n",
    b"    end\n",
    b"    DSP._v286_installed=true\n",
    b"    DSP.version='2.8.6'\n",
    b"    if DSP.flog then DSP.flog('Palatka v2.8.6 MCR Classic + Arbitrage Agent installed') end\n",
    b"    return true\n",
    b"  end\n",
]
bootstrap = b"".join(parts)
raw = original.replace(MARKER, b"PALATKA_UPDATE_VERSION = '2.8.6'", 1)
raw = raw.replace(HOOK, HOOK + bootstrap, 1)
raw = raw.replace(EARLY, b"  if DSP._v285_installed then\n    return install_v286()\n  end", 1)
raw = raw[:-len(TRAIL)] + b"  return install_v286()\nend\n"
OUT.write_bytes(raw)

version = {
    "schema": 1,
    "version": "2.8.6",
    "mode": "overlay",
    "url": OLD_URL,
    "size": len(raw),
    "published_at": "2026-10-31",
    "changelog": [
        "2.8.6 объединяет исправления 2.8.5 (точный арбитраж, ломбард, хранилища) с новым интерфейсом.",
        "MCR Classic: мобильная навигация, компактная торговля и редактирование покупки/продажи; старая оболочка остаётся.",
        "Компактный полупрозрачный журнал, свободное перемещение, настройки непрозрачности и касаний.",
        "Арбитражная сессия: боковой помощник по нескольким сделкам, отметки купленного/проданного, частичные количества.",
        "Подтверждённые операции сразу уменьшают локально доступное предложение; устаревший API не восстанавливает объём.",
        "Прибыль агента расчётная; автоматический зачёт не производится без подтверждения игрока.",
        "OTA сохраняет пользовательские настройки и совместимость с существующим скриптом Palatka AI."
    ],
}
MANIFEST.write_text(json.dumps(version, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"Generated v2.8.6 OTA: {OUT.name} = {len(raw)} bytes; v2.8.5 base preserved")
