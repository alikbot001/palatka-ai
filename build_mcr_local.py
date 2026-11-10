#!/usr/bin/env python3
"""Independent local-mode build; retains native client UI/game workflows.

No fake keys, license responses or remote entitlements are generated. Local game
readiness replaces the licensing lifecycle; MCR network services are fenced off.
"""
from pathlib import Path
import hashlib
import json
import re
import subprocess

from build_mcr_copy import ROOT, assemble

VERSION='3.0.0-local.11'
BUILD=11
UPDATE_BASE='https://raw.githubusercontent.com/alikbot001/palatka-ai/feat/mcr-full-copy-arbitrage-20261108/outputs/'

TOKEN=re.compile(r'''--\[(=*)\[.*?\]\1\]|--[^\n]*|\[(=*)\[.*?\]\2\]|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|[A-Za-z_][A-Za-z_0-9]*|\S''',re.S)


def block_end(source,start):
    depth=0
    for m in TOKEN.finditer(source,start):
        t=m[0]
        if t in ('function','if','do','repeat'):depth+=1
        elif t in ('end','until'):
            depth-=1
            if depth==0:return m.end()
    raise ValueError('Unclosed block at '+str(start))


def extract_function(source,name):
    m=re.search(r'\bfunction\s+'+re.escape(name)+r'\s*\(',source)
    if not m:raise ValueError('Missing function '+name)
    return source[m.start():block_end(source,m.start())]


def config_namespace(source):
    start=source.index('({',source.index('local r=(function(r)'))+2
    stop=source.index('})',start)
    entries=list(re.finditer(r'"((?:\\.|[^"\\])*)"',source[start:stop]))
    m=entries[31]
    hx=re.sub(r'\\(\d{1,3})',lambda x:chr(int(x[1])),m[1])
    plain=bytes((int(hx[i:i+2],16)-126*(i//2+1)-107)%256 for i in range(0,len(hx),2))
    if plain!=b'MCRM CFGs':raise ValueError('Unexpected config entry')
    name=b'Palatka MCR Local'
    encoded=''.join(f'{(b+126*(i+1)+107)%256:02x}'for i,b in enumerate(name))
    literal='"'+''.join('\\%03d'%ord(ch)for ch in encoded)+'"'
    return source[:start+m.start()]+literal+source[start+m.end():]


def build():
    raw=(ROOT/'mcr_copy/vendor/mcrm-1.15.5.lua').read_bytes()
    base,_=assemble(raw)
    source=config_namespace(base.decode('cp1251'))
    # Snapshot buttons must revalidate the captured owner before marking a shop.
    for pattern,replacement,expected in [
        (r'sampSendChat\(r\[[^\]]+\]\.\.a\.shop_id\)',
         'PalatkaMCR.navigate(a.shop_id,a.nickname,a.server)',3),
        (r'sampSendChat\(r\[[^\]]+\]\.\.T\.LavkaUid\)',
         'PalatkaMCR.navigate(T.LavkaUid,T.username,T.serverId)',1),
    ]:
        source,count=re.subn(pattern,replacement,source)
        if count!=expected:raise ValueError('Unexpected snapshot navigation anchors')
    changed=[]
    def replace_function(name,replacement):
        nonlocal source
        old=extract_function(source,name)
        source=source.replace(old,replacement,1);changed.append(name)
    replace_function('A_','function A_()return PalatkaMCR.local_ready()end')
    replace_function('p_',"function p_(value)if value==false then return false end if value==0 then return 0 end return PalatkaMCR.local_ready()end")
    setup="""function lIl_IllI()
L6.local_ready=PalatkaMCR.local_ready()
L6.authState='local';L6.status_code=0;L6.status_response=''
L6.status_text='Локальный режим — ключ MCR не используется'
U.main.userKey=''
U.telegram.use_mcr=false
end"""
    replace_function('lIl_IllI',setup)
    replace_function('lIl__llI','function lIl__llI()lIl_IllI()end')
    replace_function('lII__IlI','function lII__IlI()return PalatkaMCR.local_ready()end')
    replace_function('lIllIII_','function lIllIII_()return end')
    replace_function('lI__IIlI','function lI__IIlI()lIl_IllI()end')
    replace_function('lIlIII_l',"""function lIlIII_l()
B.TextWrapped(u8('Palatka MCR Local работает без ключа MCR. Дождитесь загрузки игрового клиента.'))
B.TextWrapped(u8('Лавки и цены: Market Helper и локальные снимки. Обновление скрипта: /crrupdate.'))
end""")
    replace_function('lI__IIll','function lI__IIll()return end')
    replace_function('lI_IlIII',"function lI_IlIII()O=PalatkaMCR.catalogue(M,nameT,O);lIllIIlI()end")
    replace_function('lIl_IIII','function lIl_IIII()if O3==F3.sell then lI_I___l(true)elseif O3==F3.buy then lI_IlIII()end end')
    replace_function('lI_IlIIl','function lI_IlIIl()lIllIIll();U.lavka.lastUpdateAllItemsID=os.time();lIllIIIl()end')
    for name in ['SettingsUI.TelegramMcrBot']:
        replace_function(name,"function "+name+"()B.TextWrapped(u8('Бот MCR недоступен в локальной версии. Настройте своего Telegram-бота; ключ MCR не нужен.'))end")
    telegram_view=extract_function(source,'llIllIll')
    marker=telegram_view.index('U.telegram.use_mcr=true U.telegram.use_self=false')
    start=telegram_view.rfind('if B.Checkbox(',0,marker)
    end=block_end(telegram_view,start)
    replace_function('llIllIll',telegram_view[:start]+"B.TextWrapped(u8('Бот MCR недоступен; используйте своего бота.'))"+telegram_view[end:])
    # The original watchdog measured CPU time, which barely moves while the
    # client waits for a network response. Keep its queue/cancellation protocol.
    watchdog=extract_function(source,'lIl_l__I')
    if watchdog.count('os.clock()')!=1:raise ValueError('Unexpected HTTP watchdog clock')
    replace_function('lIl_l__I',watchdog.replace('os.clock()','PalatkaMCR.elapsed()'))
    # A missing/changed stats dialog must not hold up the main processors forever.
    # Do not clear isCheckUID: only the genuine stats parser grants readiness.
    uid=extract_function(source,'lII____l')
    guard="""local expires=PalatkaMCR.elapsed()+30
local initialAttempts=h.attempts
local function expired()
 if PalatkaMCR.elapsed()<expires and h.attempts-initialAttempts<5 then return false end
 h.stage='timeout';h.loopActive=false
 lI__I_lI('Не получены данные персонажа. Введите /stats для повторного определения UID.',e_.secondaryInfo)
 return true
end """
    uid=uid.replace('local h=L6.uidCheck ', 'local h=L6.uidCheck '+guard,1)
    for marker in ['while not isSampAvailable()do','while not h.forceRequested and not lII_____(B)do','while L6.isCheckUID do']:
        if uid.count(marker)!=1:raise ValueError('Unexpected UID discovery loop')
        uid=uid.replace(marker,marker+' if expired()then return end ',1)
    replace_function('lII____l',uid)
    native_ready=extract_function(source,'lII___lI')
    replace_function('lII___lI',native_ready.replace('function lII___lI()',
        'function lII___lI()if L6.isCheckUID then return false end ',1))
    settings_view=extract_function(source,'llIIl_ll')
    clear_key='if B.Button(u8(r[962229-958337]))then'
    at=settings_view.index(clear_key)
    end=block_end(settings_view,at)
    source=source.replace(settings_view,settings_view[:at]+"B.TextWrapped(u8('Локальная версия: ключ MCR не нужен. /crrupdate — обновить скрипт.'))"+settings_view[end:],1)
    settings_view=extract_function(source,'llIIl_ll')
    marker=settings_view.index('U.main.cloudObxod=not U.main.cloudObxod')
    start=settings_view.rfind('if B.Checkbox(',0,marker)
    end=block_end(settings_view,start)
    if start<0 or end-start>1000:raise ValueError('Unexpected MCR mirror setting')
    source=source.replace(settings_view,settings_view[:start]+"B.TextWrapped(u8('Рыночные данные: Market Helper и свои сканы. Зеркало MCR не используется.'))"+settings_view[end:],1)
    # These five smallest blocks contain only licensing/hash guards. Inventory,
    # ownership, amount, dialog and acknowledgement checks outside them remain.
    removed=[]
    for pattern in [r'\bdo local r=H_\.z',r'\bdo local r=f_\(E_\(U\.main\.userKey\)\)',r'\bdo local r=E_\(U\.main\.userKey\)local h=H_\.z']:
        while True:
            m=re.search(pattern,source)
            if not m:break
            end=block_end(source,m.start());block=source[m.start():end]
            if 'return'not in block or len(block)>1600:raise ValueError('Unexpected license block')
            removed.append(block);source=source[:m.start()]+source[end:]
    if len(removed)!=5:raise ValueError('Expected exactly five local license guards')
    # The new-style sale worker has one inline license guard; its error cleanup
    # belongs to that guard. All actual stall ACK/slot checks are retained.
    body=extract_function(source,'lI_lIlI_')
    marker=body.index('local x=E_(U.main.userKey)local L=H_.z')
    start=marker+re.search(r'\bif\b',body[marker:]).start();end=block_end(body,start)
    old=body[start:end]
    if 'Q6.isWaitOwnerPacket=false'not in old:raise ValueError('Unexpected sale guard')
    source=source.replace(body,body[:start]+body[end:],1);removed.append(old)
    # Notification authorization was embedded before its original routing loop.
    body=extract_function(source,'lIl_llI_')
    start=body.index('local a=(H_.z');end=body.index('local T=p_',start)
    source=source.replace(body,body[:start]+body[end:],1);removed.append(body[start:end])
    sender=extract_function(source,'lIl_lllI')
    start=sender.index('if U.telegram.use_self then');end=block_end(sender,start)
    own=sender[start:end]
    own=own[:-3]+'return true end'
    replace_function('lIl_lllI','function lIl_lllI(h)'+own+' return false end')
    router=extract_function(source,'lIl_llI_')
    if router.count('lIl_lllI(B)return true')!=1:raise ValueError('Unexpected notification result')
    source=source.replace(router,router.replace('lIl_lllI(B)return true','return lIl_lllI(B)'),1)
    # UI readiness now means the local game client exists, never a remote license.
    source=re.sub(r'\bL6\.status\b','L6.local_ready',source)
    source=source.replace('PalatkaMCR.start();','PalatkaMCR.start();lIl_IllI();',1)
    ready=f"\nPalatkaMCR.version='{VERSION}';PalatkaMCR.build={BUILD};PalatkaMCR.update_base='{UPDATE_BASE}'\n"
    ready+="PalatkaMCR.local_ready=function()return type(isSampAvailable)=='function'and isSampAvailable()or false end\n"
    elapsed=(ROOT/'mcr_copy/src/elapsed.lua').read_text()
    ready+='PalatkaMCR.elapsed=(function()\n'+elapsed+"\nend)()(require 'ffi')\n"
    marker='local r=(function(r)'
    source=source.replace(marker,ready+marker,1)
    network=(ROOT/'mcr_copy/src/local_network.lua').read_text()
    source+='\n(function(G)\n'+network+'\nend)(G)\n'
    source=f"-- Configuration: Palatka MCR Local; independent client build.\nscript_name('Palatka MCR Local')\nscript_version('{VERSION}')\n"+source
    catalog=json.loads((ROOT/'data/arz_items.json').read_bytes().decode('cp1251'))
    lines=['\ndo -- Offline item catalogue; no MCR database request is required.']
    for key,name in sorted(catalog.items(),key=lambda x:int(x[0])):
        literal=json.dumps(name,ensure_ascii=False).replace('\\/','/')
        lines.append(f'if M["{key}"]==nil then M["{key}"]={literal} end')
    lines.append('end\n')
    source+='\n'.join(lines)
    catalogue=(ROOT/'mcr_copy/src/catalogue.lua').read_text()
    source+='\nPalatkaMCR.catalogue=(function()\n'+catalogue+'\nend)();\nO=PalatkaMCR.catalogue(M,nameT,O);\n'
    market=(ROOT/'mcr_copy/src/market.lua').read_text()
    bridge=(ROOT/'mcr_copy/src/local_market_host.lua').read_text()
    source+='\nPalatkaMCR.market=(function()\n'+market+'\nend)();\n'+bridge+'\n'
    # No key prompt may mask a genuine absence of fresh market observations.
    pattern=r'\bif U\.main\.userKey==nil or U\.main\.userKey==""then'
    while True:
        match=re.search(pattern,source)
        if not match:break
        end=block_end(source,match.start())
        if end-match.start()>1000:raise ValueError('Unexpected price prompt')
        source=source[:match.start()]+"B.CenterCenterText(u8(type(Y6.result)=='string'and Y6.result or'Нет свежих цен. Обновите базу Market Helper.'))"+source[end:]
    price_view=extract_function(source,'llIlIIIl')
    annotated=re.sub(r'B\.BeginChild\((r\[[^\]]+\]),a\)',
        lambda m:m[0]+"PalatkaMCR.draw_price_identity_selector();B.TextWrapped(u8('Средние цены объявлений Market Helper и своих сканов; не история сделок.'))",
        price_view)
    if annotated.count('PalatkaMCR.draw_price_identity_selector()')!=3:
        raise ValueError('Unexpected native price view children')
    source=source.replace(price_view,annotated,1)
    for field,module in [('sha256','sha256'),('new_updater','updater'),('install_file','update_file')]:
        code=(ROOT/'mcr_copy/src'/f'{module}.lua').read_text()
        source+=f'\nPalatkaMCR.{field}=(function()\n'+code+'\nend)();\n'
    source+=(ROOT/'mcr_copy/src/local_update_host.lua').read_text()
    return (source.rstrip()+'\n').encode('cp1251'),{'license_blocks_removed':len(removed),'changed_functions':changed,
        'catalogue_items':len(catalog),'config_namespace':'Palatka MCR Local',
        'base_authentication':'removed for local workflows','mcr_network':'blocked',
        'native_acceptance':False}


def main():
    raw,report=build()
    out=ROOT/'outputs/palatka_mcr_local.lua';out.write_bytes(raw)
    subprocess.run(['luajit','-b',str(out),'/dev/null'],check=True)
    report.update(version=VERSION,sha256=hashlib.sha256(raw).hexdigest(),bytes=len(raw))
    (ROOT/'outputs/palatka_mcr_local.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    manifest={'schema':1,'channel':'mcr-local','build':BUILD,'version':VERSION,
        'url':UPDATE_BASE+'palatka_mcr_local.lua','size':len(raw),'sha256':report['sha256'],
        'notes':'Исправлен пустой рынок: автоматический расчёт, ходовость без обязательного фильтра, независимое истечение строк и причины отбора. Защита от смешивания владельцев лавок и неверного возраста сканов.'}
    (ROOT/'outputs/palatka_mcr_update.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(report,ensure_ascii=False,indent=2))


if __name__=='__main__':main()
