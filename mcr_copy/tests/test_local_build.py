import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]

class LocalBuildTests(unittest.TestCase):
    def test_empty_key_local_lifecycle_and_settings(self):
        path=ROOT/'build_mcr_local.py'
        self.assertTrue(path.exists(),'missing independent client builder')
        spec=importlib.util.spec_from_file_location('local_builder',path)
        mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
        raw,report=mod.build()
        source=raw.decode('cp1251')
        self.assertGreaterEqual(report['license_blocks_removed'],5)
        self.assertTrue('Palatka MCR Local'in source)
        self.assertFalse('if L6.status then'in source)
        names=['A_','p_','lIl_IllI','lIl__llI','lII__IlI','lIllIIIl','lIlI____']
        parts=[mod.extract_function(source,n) for n in names]
        table_start=source.index('local r=(function(r)')
        table_end=source.index('})',source.index('({',table_start))+2
        table_source=source[table_start:table_end]
        harness=table_source+'''
assert(r[32]=='Palatka MCR Local','configuration namespace was not separated')
local connected=true
local saved={}
local L6={};local U={main={userKey='',activePreset='Main.json'}}
local H_={z=0,v=0,q=0,k=''};local Z_,P_,n_=0,0,''
local presetDataVersion=0;local d,p={},{};local S='presets/';local g='config/'
local a={save=function(value,path)saved[path]=value end}
local function lI__lIII()return false end
local function lI__IlIl()return 'now'end
PalatkaMCR={local_ready=function()return connected end}
'''+ '\n'.join(parts)+'''
lIl_IllI()
assert(L6.local_ready and L6.authState=='local')
assert(U.main.userKey=='','a key was invented')
assert(A_() and p_(0)==0 and p_(false)==false)
lIllIIIl();lIlI____()
assert(saved['config/MCRM-settings.json']==U,'full settings not saved without key')
assert(saved['presets/Main.json'].itemsForSell==d,'preset blocked without key')
connected=false;lIl__llI();assert(not A_() and not L6.local_ready)
print('empty-key lifecycle, local readiness, full settings and presets: OK')
'''
        with tempfile.TemporaryDirectory() as tmp:
            f=Path(tmp)/'test.lua';f.write_bytes(harness.encode('cp1251'))
            subprocess.run(['luajit',str(f)],check=True,cwd=ROOT)
        self.assertTrue('Не используется сервер MCR'in source)

    def test_mcr_network_is_not_replaced_by_fake_success(self):
        code=(ROOT/'mcr_copy/src/local_network.lua').read_text()
        harness='''local calls=0
local function network(...)calls=calls+1;return 'allowed'end
local lIl_l_lI=network;local lIl__IIl=network;local G={request=network}
PalatkaMCR={update_base='https://raw.githubusercontent.com/alikbot001/palatka-ai/feat/mcr-full-copy-arbitrage-20261108/outputs/'}
'''+code+'''
local failure
local ok=lIl_l_lI('POST','https://arz-mcr.ru/v1/auth/login',{},
 function()error('fake success')end,function(e)failure=e end)
assert(ok==false and failure and calls==0)
assert(lIl__IIl('https://online.arz-mcr.ru/api/lavkas',nil,function()end)==false and calls==0)
assert(not G.request({url='https://arz-mcr.ru/shops/create/'})and calls==0)
assert(G.request({url='https://api.telegram.org/test'})=='allowed'and calls==1)
assert(lIl_l_lI('GET','https://server-api.arizona.games/test')=='allowed'and calls==2)
assert(lIl_l_lI('GET','https://va-ta.com/api/shops/pull?server=102')=='allowed'and calls==3)
assert(lIl_l_lI('POST','https://va-ta.com/api/premium/auth',{},nil,function()end)==false and calls==3)
assert(lIl_l_lI('GET',PalatkaMCR.update_base..'palatka_mcr_update.json')=='allowed'and calls==4)
assert(lIl_l_lI('GET',PalatkaMCR.update_base..'palatka_mcr_local.lua')=='allowed'and calls==5)
assert(lIl_l_lI('GET',PalatkaMCR.update_base..'another.lua',{},nil,function()end)==false and calls==5)
print('MCR requests blocked; no fake success; game/own bot transport preserved: OK')
'''
        with tempfile.TemporaryDirectory()as tmp:
            p=Path(tmp)/'network.lua';p.write_bytes(harness.encode('cp1251'))
            subprocess.run(['luajit',str(p)],check=True)

    def test_empty_key_sale_requires_owner_and_item_acknowledgements(self):
        spec=importlib.util.spec_from_file_location('sale_builder',ROOT/'build_mcr_local.py')
        mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
        source=mod.build()[0].decode('cp1251')
        table_start=source.index('local r=(function(r)')
        table_end=source.index('})',source.index('({',table_start))+2
        harness=source[table_start:table_end]+'''
local U={main={userKey=''},delay={sampSendSell=1,timeOutSell=3}}
local H_={z=0};local Q6={};local A={};local stateProceses={}
local isSetProcessPause,isParseInventoryDialogs=false,false
local O6,o6,q6,C6,W6,D6,R6,I6
local sends,owner_ack,item_ack,pending,rows=0,false,false,false,{}
local logs={};local e_={secondaryInfo=1,debug=2}
local T={encode=function(item)
 assert(item.amount==2 and item.id==17 and item.slot==4)
 return 'encoded-listing'
end}
local cef={send_click=function(event,action,rid,payload)
 assert(event==60 and action==2 and rid==123 and payload=='encoded-listing')
 sends=sends+1;pending=true
end}
local function wait(ms)
 assert(type(ms)=='number' and ms>=0)
 if owner_ack and Q6.isWaitOwnerPacket then
  Q6.isOwnerPacketMatched=true;Q6.rid=123
 end
 if pending and item_ack then I6=true;pending=false end
end
local function lI_I___l(value)assert(value==false)end
local function lI_lIIl_()end
local function lI_lIIIl()end
local function lI_lII__(command)assert(type(command)=='string')end
local function lI_lII_l()return rows end
local function lI_lIl_l(name,slot,lvl)
 assert(name=='test' and slot==4 and lvl==0);return 1
end
local function lI__I_lI(message,level)
 assert(type(message)=='string' and (level==1 or level==2))
 logs[#logs+1]=message
end
local function E_(key)assert(key=='');return key end
local function f_(key)assert(key=='');return 0 end
PalatkaMCR={local_ready=function()return true end}
'''+mod.extract_function(source,'p_')+'\n'+mod.extract_function(source,'lI_lIlI_')+'''
local function scenario(owner,item,inventory)
 owner_ack=owner;item_ack=item;rows=inventory
 sends=0;pending=false;o6=true;Q6={};A={1};logs={};stateProceses={}
 lI_lIlI_(false)
 assert(U.main.userKey=='','sale created a license key')
 assert(not Q6.isWaitOwnerPacket,'owner wait was left active')
 return sends,stateProceses.sendPresetSell
end
local row={amount=2,id=17,slot=4,name='test',lvl=0,itemIndex=1}
local count,finished=scenario(false,true,{row})
assert(count==0 and not finished,'listing sent without owner acknowledgement')
count,finished=scenario(true,true,{})
assert(count==0 and not finished,'empty inventory submitted')
count,finished=scenario(true,true,{row})
assert(count==1 and finished,'empty-key local sale did not process real ACK path')
count,finished=scenario(true,false,{row})
assert(count==3,'missing item ACK did not respect original retry bound')
assert(#logs>=2,'timeout was not reported')
print('empty-key sale: owner timeout, empty inventory, ACK, bounded retries: OK')
'''
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'sale.lua';path.write_bytes(harness.encode('cp1251'))
            subprocess.run(['luajit',str(path)],check=True,cwd=ROOT)

if __name__=='__main__':unittest.main()
