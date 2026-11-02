#!/usr/bin/env python3
"""Palatka AI v2.9.15: apply tested stall-ready fix to the published 2.9.14 OTA."""
from pathlib import Path
import json
import subprocess

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/"updates"/"palatka_update.lua"
BASE="0612f99cf7955475eac78b1e31b253a1d7955b2e"
OLD=b"PALATKA_UPDATE_VERSION = '2.9.14'"
NEW=b"PALATKA_UPDATE_VERSION = '2.9.15'"
CALL=b"return install_trade_2914()"
NEXT=b"return install_stall_2915()"
MARK=b"  -- Install settings guard before any other overlay can save preferences."
MODULES=[
  ("stall_ack","src/70c_stall_ready_v2915.lua"),
  ("trace","src/39b_trade_probe.lua"),
]
def normalized(name):
    raw=(ROOT/name).read_bytes()
    try:
        text=raw.decode("utf-8")
    except UnicodeDecodeError:
        text=raw.decode("cp1251")
    try:
        return text.encode("cp1251")
    except UnicodeEncodeError:
        def repair(ch):
            v=ord(ch)
            if 128<=v<=255:
                out=bytes([v]).decode("cp1251",errors="replace")
                if out!="\ufffd":
                    return out
            return ch
        return "".join(repair(ch)for ch in text).encode("cp1251")

raw=subprocess.check_output(["git","show",BASE+":updates/palatka_update.lua"],cwd=ROOT)
assert raw.count(OLD)==1
assert raw.count(CALL)==2
assert raw.count(MARK)==1
parts=[
    b"  -- v2.9.15: native stall acknowledgement, trace and full sale regression.\n",
    b"  local function install_stall_2915()\n",
    b"    if not install_trade_2914() then return false end\n",
    b"    if DSP._stall_2915_installed then DSP.version='2.9.15';return true end\n",
    b"    local ok,err=pcall(function()\n",
]
for name,filename in MODULES:
    code=normalized(filename)
    fn=f"_v2915_{name}"
    parts += [
        f"      local function {fn}()\n".encode("ascii"),code,
        b"" if code.endswith(b"\n") else b"\n",
        b"      end\n",
        f"      if {fn}()==false then error('2.9.15 {name} module rejected')end\n".encode("ascii"),
    ]
parts += [
    b"      if DSP.trade_probe and DSP.trade_probe.install then DSP.trade_probe.install()end\n",
    b"    end)\n",
    b"    if not ok then\n",
    b"      if DSP.flog then DSP.flog('2.9.15 stall install error: '..tostring(err))end\n",
    b"      return false\n",
    b"    end\n",
    b"    DSP._stall_2915_installed=true\n",
    b"    DSP.version='2.9.15'\n",
    b"    DSP.active_ui_build='2.9.15'\n",
    b"    return true\n",
    b"  end\n",
]
raw=raw.replace(OLD,NEW,1).replace(CALL,NEXT).replace(MARK,b"".join(parts)+MARK,1)
assert raw.count(NEXT)==2
OUT.write_bytes(raw)
manifest={
  "schema":1,"version":"2.9.15","mode":"overlay",
  "url":"https://raw.githubusercontent.com/alikbot001/palatka-ai/main/updates/palatka_update.lua",
  "size":len(raw),"published_at":"2026-11-02",
  "changelog":[
    "Исправлено определение готовности инвентаря лавки по игровому пакету iface60/sub1.",
    "Добавлена диагностическая команда /crrtrace, отсутствовавшая в собранном Lua.",
    "Проверяется полный сценарий продажи: открытие лавки, новый диалог цены и ответ сервера.",
    "При отсутствии подтверждения готовности инвентаря скрипт останавливается без выставления.",
    "Пресеты и настройки сохраняются."
  ]
}
(ROOT/"version.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
print("Palatka 2.9.15 OTA generated",len(raw),"bytes")
