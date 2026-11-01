#!/usr/bin/env python3
"""Build the actual 2.9.7 *overlay* used by the in-game updater.

The original 2.9.6 overlay is encoded as CP1251. Retain its bytes exactly and
append the 2.9.7 migration; never decode/re-encode its older 500KB payload.
The user does NOT need to copy the full 72MB standalone onto their phone.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BASE_COPY = ROOT / "updates" / "palatka_update_v296.lua"
OTA = ROOT / "updates" / "palatka_update.lua"
MANIFEST = ROOT / "version.json"
VERSION = "2.9.7"

MODULES = [
    ("listing", "src/41_trade_listing.lua"),
    ("buy", "src/42_trade_buy.lua"),
    ("arb", "src/69a_arbitrage_agent.lua"),
    ("availability", "src/69c_arbitrage_status.lua"),
    ("arb_ui", "src/69b_arbitrage_agent_ui.lua"),
    ("promo", "src/49c_promo_mh_scheduler_v294.lua"),
    ("controls", "src/71_control_center.lua"),
    ("diag", "src/69d_runtime_diagnostic.lua"),
]

# The legacy renderer is already registered by 2.9.6: it calls the current
# A.draw. Shield it against exceptions so its old error handler doesn't
# interpret a render exception as permission to close the companion.
UI_SHIELD = """    do
      local agent = DSP.arb_agent
      if agent and type(agent.draw)=='function' then
        local old_draw=agent.draw
        agent.draw=function(...)
          local ok,err=xpcall(function() return old_draw() end,debug.traceback)
          if not ok then
            agent.ui_error=tostring(err)
            if DSP.flog and agent._v297_last_draw_error~=agent.ui_error then
              agent._v297_last_draw_error=agent.ui_error
              DSP.flog('ARB AGENT UI 2.9.7: '..agent.ui_error)
            end
          end
        end
      end
    end
    do
      local V=DSP.ui22 or DSP.ui21
      if V and V.set_screen then
        local old_tools=V.tools
        V.tools=function(page,...)
          if page=='control' and DSP.controls then
            return DSP.controls.draw()
          end
          if old_tools then return old_tools(page,...) end
        end
        -- The existing primary nav is a local captured table in the 2.9.6
        -- shell. Add clear on-screen shortcuts instead of rebuilding ImGui.
        local function shortcut(id)
          if V.button('Управление и интервалы','v297_control_'..id,246,false,true,39) then
            V.set_screen('control')
            return true
          end
          return false
        end
        if type(V.home)=='function' then
          local old_home=V.home
          V.home=function(...)
            if shortcut('home') then return end
            return old_home(...)
          end
        end
        if type(V.trade)=='function' then
          local old_trade=V.trade
          V.trade=function(...)
            if shortcut('trade') then return end
            return old_trade(...)
          end
        end
        if type(V.promo_screen)=='function' then
          local old_promo=V.promo_screen
          V.promo_screen=function(...)
            if shortcut('promo') then return end
            return old_promo(...)
          end
        end
      end
    end
"""


def source_bytes(relative_path: str) -> bytes:
    raw = (ROOT / relative_path).read_bytes()
    try:
        source = raw.decode("utf-8")
    except UnicodeDecodeError:
        source = raw.decode("cp1251")
    try:
        return source.encode("cp1251")
    except UnicodeEncodeError:
        # Match build.py's legacy Latin1-to-CP1251-mojibake recovery.
        fixed = "".join(
            bytes([ord(char)]).decode("cp1251", errors="replace")
            if 0x80 <= ord(char) <= 0xFF
            and bytes([ord(char)]).decode("cp1251", errors="replace") != "\ufffd"
            else char
            for char in source
        )
        return fixed.encode("cp1251")


def generate(base: bytes) -> bytes:
    previous = b"PALATKA_UPDATE_VERSION = '2.9.6'"
    assert base.count(previous) == 1, "Expected original OTA 2.9.6 only"
    end = b"  return install_v296()\nend\n"
    assert base.endswith(end), "Unexpected 2.9.6 OTA entry-point"
    result = [
        b"  local function install_v297()\n",
        b"    if not install_v296() then return false end\n",
        b"    if DSP._v297_installed then DSP.version='2.9.7';return true end\n",
        b"    local ok,err=pcall(function()\n",
    ]
    for key, path in MODULES:
        if key == "promo":
            # Rebind the scheduler: it was already installed by 2.9.6.
            result.append(b"    if DSP.promo then DSP.promo._mh_scheduler_v294=nil end\n")
        fn = ("_v297_" + key).encode("ascii")
        result.extend([b"    do\n      local function " + fn + b"()\n",
                       source_bytes(path), b"\n      end\n      " + fn + b"()\n    end\n"])
    result.append(UI_SHIELD.encode("cp1251"))
    result.extend([
        b"    end)\n",
        b"    if not ok then\n",
        b"      if DSP.flog then DSP.flog('Palatka 2.9.7 OTA failed: '..tostring(err)) end\n",
        b"      return false\n",
        b"    end\n",
        b"    DSP._v297_installed=true\n",
        b"    DSP.version='2.9.7'\n",
        b"    if DSP.flog then DSP.flog('Palatka 2.9.7 control center installed') end\n",
        b"    return true\n",
        b"  end\n",
        b"  return install_v297()\nend\n"
    ])
    replacement = b"".join(result)
    return base[:-len(end)].replace(previous, b"PALATKA_UPDATE_VERSION = '2.9.7'", 1) + replacement


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true",
                        help="Build and verify without changing tracked files")
    args = parser.parse_args()
    if BASE_COPY.exists():
        base = BASE_COPY.read_bytes()
    else:
        base = OTA.read_bytes()
    payload = generate(base)
    print(f"2.9.7 OTA: {len(payload)} bytes")
    if payload.count(b"PALATKA_UPDATE_VERSION = '2.9.7'") != 1:
        raise ValueError("Bad version label")
    for module in (b"_v297_controls()", b"_v297_listing()",
                   b"_v297_availability()", b"_v297_promo()"):
        if module not in payload:
            raise ValueError(f"Missing migration {module!r}")
    result = subprocess.run(["luajit", "-bl", "-", "/dev/null"],
                            input=payload, capture_output=True)
    if result.returncode:
        # LuaJIT's input-as-stdin support may vary between platform builds.
        candidate = ROOT / "updates" / ".palatka_297_check.lua"
        candidate.write_bytes(payload)
        result = subprocess.run(["luajit", "-bl", str(candidate), "/dev/null"],
                                capture_output=True)
        candidate.unlink(missing_ok=True)
    if result.returncode:
        raise RuntimeError("OTA LuaJIT compilation failed: " +
                           result.stderr.decode("utf-8", errors="replace")[-1600:])
    if args.check:
        print("OTA syntax: OK; dry-run, no files published")
        return
    if not BASE_COPY.exists():
        BASE_COPY.write_bytes(base)
    OTA.write_bytes(payload)
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    manifest["version"] = VERSION
    manifest["mode"] = "overlay"
    manifest["url"] = (
        "https://raw.githubusercontent.com/alikbot001/palatka-ai/main/"
        "updates/palatka_update.lua"
    )
    manifest["size"] = len(payload)
    manifest["published_at"] = dt.datetime.now(dt.timezone.utc).date().isoformat()
    manifest["changelog"] = [
        "Добавлен единый центр управления торговлей, паузами, авто-пиаром и лавками.",
        "Добавлены стандартный, бережный и медленный профили, общий STOP.",
        "Подтверждения арбитража откатываются при сбое сохранения.",
        "Нет предмета/нет лавки сохраняет маршрут и не закрывает мини-агент.",
        "Исправлена динамическая диагностика версии; пользовательские настройки сохранены.",
    ]
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
                        encoding="utf-8")
    assert OTA.stat().st_size == manifest["size"]
    print("Version manifest: 2.9.7, exact OTA byte size")
if __name__ == "__main__":
    main()
