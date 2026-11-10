import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class NativeRegressionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location('builder', ROOT / 'build_mcr_local.py')
        cls.builder = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.builder)
        cls.source = cls.builder.build()[0].decode('cp1251')
        start = cls.source.index('local r=(function(r)')
        end = cls.source.index('})', cls.source.index('({', start)) + 2
        cls.strings = cls.source[start:end]

    def run_lua(self, setup, names, assertions):
        code = self.strings + '\n' + setup + '\n'
        code += '\n'.join(self.builder.extract_function(self.source, n) for n in names)
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'native.lua'
            path.write_bytes((code + '\n' + assertions).encode('cp1251'))
            run = subprocess.run(['luajit', str(path)], cwd=ROOT, capture_output=True)
            self.assertEqual(run.returncode, 0, (run.stdout + run.stderr).decode('cp1251'))

    def test_sell_and_buy_refresh_keep_distinct_native_paths(self):
        self.run_lua('''
local F3={sell=1,buy=2};local O3=F3.sell
local scans,catalogues=0,0
local function lI_I___l(value)assert(value==true);scans=scans+1 end
local function lI_IlIII()catalogues=catalogues+1 end
''', ['lIl_IIII'], '''
lIl_IIII();assert(scans==1 and catalogues==0,'sell refresh did not scan inventory')
O3=F3.buy;lIl_IIII();assert(scans==1 and catalogues==1,'buy refresh used wrong path')
''')

    def test_own_telegram_controls_and_notifications_are_reachable(self):
        self.run_lua('''
local inputs,checks=0,0
local B={Checkbox=function()checks=checks+1;return false end,
InputText=function()inputs=inputs+1;return false end,Button=function()return false end,
SameLine=function()end,GetWindowWidth=function()return 400 end,
Separator=function()end,Spacing=function()end,Columns=function()end,NextColumn=function()end,
TextWrapped=function()end,ImVec2=function()return {}end}
local new={bool=function(v)return {[0]=v}end,char=setmetatable({},{__index=function()
 return function(v)return v end end})}
local U={telegram={use_self=true,use_mcr=false,token='',idGroup='',getUpdates=false,
 notifications={test={isActive=true,text='Test'}}}}
local W={telegram={notifications={}}};local SettingsUI={};local MONET_DPI_SCALE=1
local function u8(s)return s end
local function llII___l()return function()end end
''', ['SettingsUI.TelegramBot', 'SettingsUI.TelegramMcrBot', 'llIllIll'], '''
llIllIll();assert(inputs==2,'own bot token/group inputs are unreachable')
assert(checks>=3,'notification controls are unreachable')
assert(not U.telegram.use_mcr,'MCR bot was activated')
''')

    def test_http_watchdog_expires_during_low_cpu_wait(self):
        clock_module = ROOT / 'mcr_copy/src/elapsed.lua'
        clock_code = clock_module.read_text() if clock_module.exists() else 'return function()return os.clock()end'
        self.run_lua('''
local elapsed_factory=(function()
''' + clock_code + '''
end)()
local PalatkaMCR={elapsed=elapsed_factory(require 'ffi')}
local asyncHttpPending={};local ASYNC_HTTP_MAX_RETRIES=3;local ASYNC_HTTP_RETRY_DELAY=.25
local failed,canceled,resolved=0,0,0
local function lIl_l_ll(_,err)assert(type(err)=='string');failed=failed+1 end
local function lIl_l_I_(fn,...)return pcall(fn,...)end
local function lIl_ll__()end
local function wait()coroutine.yield()end
''', ['lIl_l_l_', 'lIl_l__I'], '''
local ffi=require 'ffi';ffi.cdef[[int usleep(unsigned int);]]
local th={status=function()return 'running'end,cancel=function()canceled=canceled+1 end}
asyncHttpPending={{build=function()return th end,attempt=0,retryAt=0,timeoutSec=.03}}
local co=coroutine.create(lIl_l__I)
assert(coroutine.resume(co));assert(coroutine.resume(co))
ffi.C.usleep(120000)
assert(coroutine.resume(co))
assert(failed==1 and canceled==1 and #asyncHttpPending==0,'wall timeout did not cancel request')
assert(coroutine.resume(co));assert(failed==1,'timeout delivered more than once')
asyncHttpPending={{th={status=function()return 'completed'end,
 get=function()return true,{text='ok'}end},resolve=function()resolved=resolved+1 end}}
assert(coroutine.resume(co));assert(resolved==1 and #asyncHttpPending==0)
''')

    def test_elapsed_clock_accepts_existing_ffi_timespec_declaration(self):
        module = (ROOT / 'mcr_copy/src/elapsed.lua').read_text()
        self.run_lua('''
local ffi=require 'ffi'
ffi.cdef[[struct timespec { long tv_sec; long tv_nsec; };
 int clock_gettime(int,struct timespec *);]]
local make=(function()
''' + module + '''
end)()
local elapsed=make(ffi)
local again=make(ffi)
''', [], '''
local first=elapsed();assert(type(first)=='number'and elapsed()>=first)
assert(again()>=first)
''')

    def test_uid_discovery_is_bounded_without_faking_readiness(self):
        self.run_lua('''
local clock,sends,logs=0,0,0
local L6={local_ready=true,isCheckUID=false,uidCheck={attempts=0,lastSentAt=0,
 forceRequested=false,stage='start'}}
local PalatkaMCR={elapsed=function()return clock end}
local isNeomLoader=true;local e_={debug=1,secondaryInfo=2}
local function isSampAvailable()return true end
local function sampIsLocalPlayerSpawned()return true end
local function sampSendChat(cmd)assert(cmd=='/stats');sends=sends+1 end
local dialog_active=false
local function sampIsDialogActive()return dialog_active end
local function sampGetCurrentDialogId()return 77 end
local function lI__I_lI()logs=logs+1 end
local recognized=false
local function wait(ms)
 clock=clock+ms/1000
 if recognized and sends>0 then
  local nick,uid=lIlIIIIl('Имя: Nick [№123]')
  if nick and uid then L6.isCheckUID=false;L6.playerUID=uid;L6.playerNick=nick end
 end
 coroutine.yield()
end
local os={time=function()return clock end}
''', ['lII____l', 'lII_____', 'lI_lllII', 'lIlIIIII', 'lII___lI', 'lIlIIIIl'], '''
local co=coroutine.create(lII____l)
for n=1,600 do if coroutine.status(co)=='dead'then break end;assert(coroutine.resume(co))end
assert(coroutine.status(co)=='dead' and clock<=30.2 and sends<=5,'UID discovery is unbounded')
assert(L6.isCheckUID and not lII___lI() and L6.playerUID==nil,'missing stats granted readiness')
isNeomLoader=false;assert(not lII___lI(),'MonetLoader granted readiness without UID');isNeomLoader=true
assert(not L6.uidCheck.loopActive and L6.uidCheck.stage=='timeout','timeout state missing')
-- A dialog can prevent every request; the elapsed deadline must still release startup.
clock=0;sends=0;dialog_active=true;L6.uidCheck.lastSentAt=0
co=coroutine.create(lII____l)
for n=1,600 do if coroutine.status(co)=='dead'then break end;assert(coroutine.resume(co))end
assert(coroutine.status(co)=='dead' and clock>=30 and clock<=30.2 and sends==0)
assert(L6.isCheckUID and not lII___lI(),'dialog timeout granted readiness')
dialog_active=false
-- A new invocation still accepts actual stats instead of disabling discovery.
recognized=true;sends=0;L6.uidCheck.forceRequested=true
co=coroutine.create(lII____l)
for n=1,600 do if coroutine.status(co)=='dead'then break end;assert(coroutine.resume(co))end
assert(coroutine.status(co)=='dead' and lII___lI() and L6.playerUID=='123')
assert(not L6.uidCheck.loopActive)
''')

    def test_price_identity_selection_is_wired_into_native_view(self):
        self.run_lua('''
local calls=0
local in_child=false
local PalatkaMCR={draw_price_identity_selector=function()
 assert(in_child,'identity controls outside allocated child height')
 calls=calls+1;error('verified child selector')
end}
local U={main={activeAVGPrice=0}}
local B={BeginChild=function()in_child=true end}
''', ['llIlIIIl'], '''
local ok,why=pcall(llIlIIIl,nil,{})
assert(not ok and tostring(why):find('verified child selector',1,true)and calls==1,
 'native identity choices missing or outside original viewport')
''')

    def test_native_price_consumer_receives_exact_total_value(self):
        self.run_lua('''
local E=assert(loadfile('mcr_copy/src/engine.lua'))()
local market=assert(loadfile('mcr_copy/src/market.lua'))()
local state=E.new()
assert(E.observe(state,{server='test',shop=1,at=1000,sell={
 {id='5',variant='0:0',name='Item',price=100,qty=2,currency='SA$'},
 {id='5',variant='0:0',name='Item',price=101,qty=1,currency='SA$'}},
 buy={{id='5',variant='0:0',name='Item',price=150,qty=2,currency='SA$'}}}))
PalatkaMCR={state=state,market=market,options={ttl=3600},
 host={server=function()return'test'end,now=function()return 1000 end,
 currency=function()return'SA$'end},refresh_market=function(done)done(true)end}
listStatusResponses={WAIT=1,SUCCESS=2,FAILURE=3};Y6={}
function lIl_l__l(state,status,result)state.status=status;state.result=result end
local U={main={activeAVGPrice=0}}
assert(loadfile('mcr_copy/src/local_market_host.lua'))()
''', ['lIl_IlI_'], '''
lIl___Il('Item');assert(Y6.status=='true')
local ok,result=lIl_IlI_()
assert(ok and result.avg_sell_price==100 and result.avg_buy_price==150)
assert(Y6.result.sell_data[1].total_value==301,'price rounding lost exact total')
assert(Y6.result.buy_data[1].total_value==300)
''')


if __name__ == '__main__':
    unittest.main()
