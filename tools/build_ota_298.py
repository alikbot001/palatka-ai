#!/usr/bin/env python3
"""Publish the 2.9.8 Android overlay with a byte-exact manifest.
Use the verified 2.9.7 OTA as a base, adding only the new migration.
"""
from __future__ import annotations
import argparse
import datetime as dt
import json
import subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parent.parent
OTA=ROOT/'updates/palatka_update.lua'
PREVIOUS=ROOT/'updates/palatka_update_v297.lua'
VERSION=ROOT/'version.json'
OLD=b"PALATKA_UPDATE_VERSION = '2.9.7'"
NEW=b"PALATKA_UPDATE_VERSION = '2.9.8'"
END=b"  return install_v297()\nend\n"
MODULES=[
    ('promo_mobile','src/72_promo_market_style_v298.lua'),
    ('fast_rec','src/73_fast_reconnect_v298.lua'),
]

def converted(path):
    data=(ROOT/path).read_bytes()
    try: s=data.decode('utf-8')
    except UnicodeDecodeError: s=data.decode('cp1251')
    return s.encode('cp1251')

def generate(base):
    assert base.count(OLD)==1, 'Wrong predecessor OTA'
    assert base.endswith(END), '2.9.7 installer tail changed'
    blocks=[
        b"  local function install_v298()\n",
        b"    if not install_v297() then return false end\n",
        b"    if DSP._v298_installed then DSP.version='2.9.8';return true end\n",
        b"    local ok,err=pcall(function()\n",
    ]
    for name,path in MODULES:
        fn=('v298_'+name).encode('ascii')
        blocks.extend([
            b"      do\n        local function "+fn+b"()\n",
            converted(path),
            b"\n        end\n        "+fn+b"()\n      end\n",
        ])
    blocks.extend([
        b"    end)\n",
        b"    if not ok then\n",
        b"      if DSP.flog then DSP.flog('Palatka 2.9.8 install failed: '..tostring(err))end\n",
        b"      return false\n",
        b"    end\n",
        b"    DSP._v298_installed=true\n",
        b"    DSP.version='2.9.8'\n",
        b"    return true\n",
        b"  end\n",
        b"  return install_v298()\nend\n"
    ])
    return base[:-len(END)].replace(OLD,NEW,1)+b''.join(blocks)

def main():
    p=argparse.ArgumentParser()
    p.add_argument('--check',action='store_true')
    args=p.parse_args()
    base=(PREVIOUS if PREVIOUS.exists() else OTA).read_bytes()
    result=generate(base)
    assert result.count(NEW)==1
    assert result.endswith(b"  return install_v298()\nend\n")
    check_path=ROOT/'updates/.check_298.lua'
    try:
        check_path.write_bytes(result)
        check=subprocess.run(['luajit','-bl',str(check_path),'/dev/null'],
            capture_output=True,text=True)
        if check.returncode:
            raise ValueError('LuaJIT OTA parse error: '+check.stderr[-1600:])
    finally:
        check_path.unlink(missing_ok=True)
    print('2.9.8 OTA compiled:',len(result),'bytes')
    if args.check: return
    if not PREVIOUS.exists():PREVIOUS.write_bytes(base)
    OTA.write_bytes(result)
    m=json.loads(VERSION.read_text(encoding='utf-8'))
    m.update({
        'version':'2.9.8','size':len(result),'mode':'overlay',
        'url':'https://raw.githubusercontent.com/alikbot001/palatka-ai/main/updates/palatka_update.lua',
        'published_at':dt.datetime.now(dt.timezone.utc).date().isoformat(),
        'changelog':[
            'Главный экран очищен от лишнего блока управления интервалами.',
            'Автопиар: шаблоны по схеме Market Helper с Пуск, Авто, Редактировать.',
            'У каждого шаблона настраиваются строки, пауза, минимальный и максимальный интервалы, случайный выбор и лимит.',
            'Подстановка <lavka> берёт номер собственной лавки, если тот подтверждён.',
            'Fast REC: кнопка у края экрана, ручной реконнект и выбор сохранённых реальных точек спавна.',
            'Исправлено ложное подтверждение реконнекта из старого флага spawned.'
        ]})
    VERSION.write_text(json.dumps(m,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    assert OTA.stat().st_size==m['size']
    print('Manifest and OTA size match.')
if __name__=='__main__':main()
