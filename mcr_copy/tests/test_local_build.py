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
PalatkaMCR={}
'''+code+'''
local failure
local ok=lIl_l_lI('POST','https://arz-mcr.ru/v1/auth/login',{},
 function()error('fake success')end,function(e)failure=e end)
assert(ok==false and failure and calls==0)
assert(lIl__IIl('https://online.arz-mcr.ru/api/lavkas',nil,function()end)==false and calls==0)
assert(not G.request({url='https://arz-mcr.ru/shops/create/'})and calls==0)
assert(G.request({url='https://api.telegram.org/test'})=='allowed'and calls==1)
assert(lIl_l_lI('GET','https://server-api.arizona.games/test')=='allowed'and calls==2)
print('MCR requests blocked; no fake success; game/own bot transport preserved: OK')
'''
        with tempfile.TemporaryDirectory()as tmp:
            p=Path(tmp)/'network.lua';p.write_bytes(harness.encode('cp1251'))
            subprocess.run(['luajit',str(p)],check=True)

if __name__=='__main__':unittest.main()
