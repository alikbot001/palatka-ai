#!/usr/bin/env python3
"""Assemble 2.9.16 OTA over released 2.9.15, without changing UI modules."""
from pathlib import Path
import subprocess, json
ROOT=Path(__file__).resolve().parents[1]
BASE="eca9364028405ec11ba3c458adfd041359de39f9"
OUT=ROOT/"updates"/"palatka_update.lua"
MARK=b"  -- Install settings guard before any other overlay can save preferences."
OLD=b"PALATKA_UPDATE_VERSION = '2.9.15'"
NEW=b"PALATKA_UPDATE_VERSION = '2.9.16'"
PREV=b"return install_stall_2915()"
NEXT=b"return install_sell_2916()"
MODULES=[
    ("rescan_compat","src/70d_sell_refresh_ota_v2916.lua"),
    ("listing","src/41_trade_listing.lua"),
    ("stock","src/70b_trade_stock_ota_v2914.lua"),
]
def cp1251(filename):
    raw=(ROOT/filename).read_bytes()
    try: text=raw.decode("utf-8")
    except UnicodeDecodeError: text=raw.decode("cp1251")
    try: return text.encode("cp1251")
    except UnicodeEncodeError:
        def rescue(char):
            v=ord(char)
            if 128<=v<=255:
                s=bytes([v]).decode("cp1251",errors="replace")
                if s!="\ufffd":return s
            return char
        return "".join(map(rescue,text)).encode("cp1251")

base=subprocess.check_output(["git","show",BASE+":updates/palatka_update.lua"],cwd=ROOT)
assert base.count(OLD)==1 and base.count(PREV)==2 and base.count(MARK)==1
parts=[
    b"  -- v2.9.16: inventory revalidation per listing; unchanged 2.9.13 UI.\n",
    b"  local function install_sell_2916()\n",
    b"    if not install_stall_2915() then return false end\n",
    b"    if DSP._sell_2916_installed then DSP.version='2.9.16';return true end\n",
    b"    local ok,err=pcall(function()\n",
]
for name,filename in MODULES:
    code=cp1251(filename)
    fn=f"_v2916_{name}"
    parts.extend([
        f"      local function {fn}()\n".encode("ascii"),
        code,
        b"" if code.endswith(b"\n") else b"\n",
        b"      end\n",
        f"      if {fn}()==false then error('{name} rejected')end\n".encode("ascii")
    ])
parts.extend([
    b"    end)\n",
    b"    if not ok then\n",
    b"      if DSP.flog then DSP.flog('Palatka v2.9.16 sale fix error: '..tostring(err))end\n",
    b"      return false\n",
    b"    end\n",
    b"    DSP._sell_2916_installed=true\n",
    b"    DSP.version='2.9.16'\n",
    b"    return true\n",
    b"  end\n",
])
raw=base.replace(OLD,NEW,1).replace(PREV,NEXT).replace(MARK,b"".join(parts)+MARK,1)
assert raw.count(NEXT)==2
OUT.write_bytes(raw)
release={
    "schema":1,
    "version":"2.9.16",
    "mode":"overlay",
    "url":"https://raw.githubusercontent.com/alikbot001/palatka-ai/main/updates/palatka_update.lua",
    "size":len(raw),
    "published_at":"2026-11-02",
    "changelog":[
        "При продаже каждого следующего предмета выполняется повторная проверка фактического инвентаря.",
        "Перед каждым выставлением заново открывается собственная лавка и подтверждается её готовность.",
        "Предотвращено использование устаревших номеров слотов после изменения количества товаров.",
        "При потере подтверждения от сервера продажа безопасно останавливается вместо незаметного пропуска.",
        "Оформление и окна сохранены по исходникам версии 2.9.13; настройки и пресеты не сбрасываются."
    ]
}
(ROOT/"version.json").write_text(json.dumps(release,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
print("Built Palatka 2.9.16 OTA",len(raw),"bytes")
