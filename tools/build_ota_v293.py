#!/usr/bin/env python3
"""Build the Palatka AI 2.9.3 OTA from the last verified 2.9.2 payload plus current source overrides."""
from pathlib import Path
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "updates" / "palatka_update.lua"
MANIFEST = ROOT / "version.json"
BASE_COMMIT = "3aea33b1132ce8d8f9f1a6933de334868d05c0ed"
OLD_VERSION = b"PALATKA_UPDATE_VERSION = '2.9.2'"
NEW_VERSION = b"PALATKA_UPDATE_VERSION = '2.9.3'"
INSERT_MARKER = b"  -- Install settings guard before any other overlay can save preferences."

MODULES = [
    ("promo_mh_options", "src/49b_promo_mh_options.lua"),
    ("drop_sales_stats", "src/59b_drop_sales_stats.lua"),
    ("touch_scroll", "src/60aa_touch_scroll.lua"),
    ("arbitrage_ui", "src/63_ui21_arbitrage.lua"),
    ("stats_ui", "src/65a_stats_v293.lua"),
    ("trade_journal", "src/66c_mh_trade_journal.lua"),
    ("promo_ui", "src/68b_promo_universal_ui.lua"),
    ("agent_ui", "src/69b_arbitrage_agent_ui.lua"),
    ("arbitrage_status", "src/69c_arbitrage_status.lua"),
    ("runtime_diagnostic", "src/69d_runtime_diagnostic.lua"),
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
    raise SystemExit("unexpected 2.9.2 OTA version marker")
if base.count(b"return install_v292()") != 2:
    raise SystemExit("unexpected 2.9.2 terminal installer count")
if base.count(INSERT_MARKER) != 1:
    raise SystemExit("unexpected OTA insertion marker")

parts = [
    b"  -- v2.9.3: Market Helper UX, touch scrolling, completed arbitrage flow, journal and statistics.\n",
    b"  local function install_v293()\n",
    b"    local parent_ok=install_v292()\n",
    b"    if not parent_ok then return false end\n",
    b"    if DSP._v293_installed then DSP.version='2.9.3';return true end\n",
    b"    local ok,err=pcall(function()\n",
]
for name, path in MODULES:
    code = normalize(path)
    fn = f"_v293_{name}".encode("ascii")
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
    b"      if DSP.flog then DSP.flog('Palatka v2.9.3 install error: '..tostring(err))end\n",
    b"      return false\n",
    b"    end\n",
    b"    DSP._v293_installed=true\n",
    b"    DSP.version='2.9.3'\n",
    b"    DSP.active_ui_build='2.9.3'\n",
    b"    if DSP.flog then DSP.flog('Palatka v2.9.3 Market Helper UX installed')end\n",
    b"    return true\n",
    b"  end\n",
]
block = b"".join(parts)

raw = base.replace(
    b"-- Palatka AI 2.8.3: compatible trunk sizes, suggestion dialog and settings protection.",
    b"-- Palatka AI 2.9.3 OTA: Market Helper UX, touch scroll, journal, statistics and arbitrage fixes.",
    1,
)
raw = raw.replace(OLD_VERSION, NEW_VERSION, 1)
raw = raw.replace(b"return install_v292()", b"return install_v293()")
raw = raw.replace(INSERT_MARKER, block + INSERT_MARKER, 1)

OUT.write_bytes(raw)
release = {
    "schema": 1,
    "version": "2.9.3",
    "mode": "overlay",
    "url": "https://raw.githubusercontent.com/alikbot001/palatka-ai/main/updates/palatka_update.lua",
    "size": len(raw),
    "published_at": "2026-11-01",
    "changelog": [
        "Новый Market Helper-подобный автопиар: пауза между строками, интервалы, лимит, случайная строка и ручная отправка.",
        "Плавная прокрутка перетаскиванием содержимого без фиксированных стрелок прокрутки.",
        "Мини-агент арбитража больше не перескакивает автоматически после отметки отсутствующего предмета или лавки.",
        "Торговый журнал переработан под компактный Market Helper-стиль с фильтрами, поиском и итогами.",
        "Статистика показывает выпадения, подтверждённые продажи и фактическое количество по последнему скану инвентаря.",
        "Исправлена публикация OTA: версия 2.9.3 теперь реально доступна встроенному обновлятору.",
    ],
}
MANIFEST.write_text(json.dumps(release, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"Generated Palatka AI 2.9.3 OTA: {len(raw)} bytes")
